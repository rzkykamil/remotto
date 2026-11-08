package server

import (
	"errors"
	"log/slog"
	"net/http"
	"time"

	"remotto/agent/internal/control"
)

// pendingData is the Pending object, see docs/api-spec.md, section "Objek
// bersama". The app counts down from RemainingMs and DelayMs; ScheduledAt is
// informational only (BR-20).
type pendingData struct {
	Action      string `json:"action"`
	RemainingMs int64  `json:"remainingMs"`
	DelayMs     int64  `json:"delayMs"`
	ScheduledAt string `json:"scheduledAt"`
}

// powerScheduledData is the body of a 202 response from a /power/* schedule route.
type powerScheduledData struct {
	Pending pendingData `json:"pending"`
}

// powerCancelData is the body of a 200 response from POST /power/cancel. Pending
// is a nil pointer on success, so it encodes as null.
type powerCancelData struct {
	Cancelled string       `json:"cancelled"`
	Pending   *pendingData `json:"pending"`
}

// pendingView converts a scheduler snapshot to the Pending object.
func pendingView(p control.PendingPower) pendingData {
	return pendingData{
		Action:      string(p.Action),
		RemainingMs: p.Remaining.Milliseconds(),
		DelayMs:     p.Delay.Milliseconds(),
		ScheduledAt: p.ScheduledAt.Format(time.RFC3339),
	}
}

// registerPowerRoutes adds the /power routes (M4, docs/api-spec.md section
// "Daya"). Schedule requests ignore the body, like the media routes. Nothing
// here runs an OS command directly: every action goes through svc.
func registerPowerRoutes(r *Router, svc *control.PowerScheduler, logger *slog.Logger) {
	r.Handle(http.MethodPost, APIPrefix+"/power/sleep", newPowerScheduleHandler(control.PowerSleep, svc, logger))
	r.Handle(http.MethodPost, APIPrefix+"/power/restart", newPowerScheduleHandler(control.PowerRestart, svc, logger))
	r.Handle(http.MethodPost, APIPrefix+"/power/shutdown", newPowerScheduleHandler(control.PowerShutdown, svc, logger))
	r.Handle(http.MethodPost, APIPrefix+"/power/cancel", newPowerCancelHandler(svc, logger))
}

// newPowerScheduleHandler returns the handler for one POST /api/v1/power/* schedule
// route. It answers as soon as the schedule is stored, without waiting for the
// delay or the OS command (BR-4). A second schedule while one is active is
// 409 power_pending and leaves the first schedule unchanged (BR-5).
func newPowerScheduleHandler(action control.PowerAction, svc *control.PowerScheduler, logger *slog.Logger) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		p, err := svc.Schedule(r.Context(), action)
		if err != nil {
			if errors.Is(err, control.ErrPowerPending) {
				WriteError(w, http.StatusConflict, CodePowerPending, control.ErrPowerPending.Error())
				return
			}
			logPowerFailure(logger, "schedule", err)
			WriteError(w, http.StatusInternalServerError, CodePowerFailed, "power scheduling failed")
			return
		}
		WriteData(w, http.StatusAccepted, powerScheduledData{Pending: pendingView(p)})
	})
}

// newPowerCancelHandler returns the handler for POST /api/v1/power/cancel. It
// removes the active schedule (BR-17). With nothing scheduled it is 409
// no_pending_power, and once the command runs it is 409 power_executing.
func newPowerCancelHandler(svc *control.PowerScheduler, logger *slog.Logger) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		action, err := svc.Cancel()
		if err != nil {
			switch {
			case errors.Is(err, control.ErrNoPendingPower):
				WriteError(w, http.StatusConflict, CodeNoPendingPower, control.ErrNoPendingPower.Error())
			case errors.Is(err, control.ErrPowerExecuting):
				WriteError(w, http.StatusConflict, CodePowerExecuting, control.ErrPowerExecuting.Error())
			default:
				logPowerFailure(logger, "cancel", err)
				WriteError(w, http.StatusInternalServerError, CodePowerFailed, "power cancel failed")
			}
			return
		}
		WriteData(w, http.StatusOK, powerCancelData{Cancelled: string(action)})
	})
}

// logPowerFailure records an unexpected scheduler error. The cause goes to the
// log only and never reaches the response.
func logPowerFailure(logger *slog.Logger, op string, err error) {
	attrs := []any{slog.String("op", op), slog.String("error", err.Error())}
	if cause := errors.Unwrap(err); cause != nil {
		attrs = append(attrs, slog.String("cause", cause.Error()))
	}
	logger.Error("power failed", attrs...)
}
