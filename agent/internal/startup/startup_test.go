package startup

import (
	"bytes"
	"context"
	"encoding/xml"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"unicode/utf16"

	"remotto/agent/internal/control"
)

// fakeRunner records every call and, when called, reads the /XML file so the
// test can check its contents while it still exists.
type fakeRunner struct {
	calls   [][]string
	xmlSeen []byte
	xmlPath string
	out     []byte
	err     error
}

func (f *fakeRunner) Run(_ context.Context, name string, args ...string) ([]byte, error) {
	f.calls = append(f.calls, append([]string{name}, args...))
	for i, a := range args {
		if a == "/XML" && i+1 < len(args) {
			f.xmlPath = args[i+1]
			data, err := os.ReadFile(f.xmlPath)
			if err == nil {
				f.xmlSeen = data
			}
		}
	}
	return f.out, f.err
}

type taskDoc struct {
	UserID    string `xml:"Triggers>LogonTrigger>UserId"`
	Logon     string `xml:"Triggers>LogonTrigger>Enabled"`
	LogonType string `xml:"Principals>Principal>LogonType"`
	RunLevel  string `xml:"Principals>Principal>RunLevel"`
	Command   string `xml:"Actions>Exec>Command"`
	Arguments string `xml:"Actions>Exec>Arguments"`
}

// decodeTaskXML checks the UTF-16 LE BOM, converts to UTF-8, and parses the
// document. It returns the parsed fields and the raw UTF-8 text.
func decodeTaskXML(t *testing.T, data []byte) (taskDoc, string) {
	t.Helper()
	if len(data) < 2 || data[0] != 0xFF || data[1] != 0xFE {
		t.Fatalf("missing UTF-16 LE BOM")
	}
	body := data[2:]
	if len(body)%2 != 0 {
		t.Fatalf("odd UTF-16 byte length")
	}
	units := make([]uint16, len(body)/2)
	for i := range units {
		units[i] = uint16(body[2*i]) | uint16(body[2*i+1])<<8
	}
	text := string(utf16.Decode(units))

	var doc taskDoc
	dec := xml.NewDecoder(strings.NewReader(text))
	// The declaration says UTF-16; the text is already UTF-8 after decoding.
	dec.CharsetReader = func(_ string, r io.Reader) (io.Reader, error) { return r, nil }
	if err := dec.Decode(&doc); err != nil {
		t.Fatalf("decode task xml: %v", err)
	}
	return doc, text
}

func TestBuildTaskXMLContent(t *testing.T) {
	data, err := BuildTaskXML(`C:\Remotto\remotto-agent.exe`, `PC\rizky`)
	if err != nil {
		t.Fatalf("BuildTaskXML: %v", err)
	}
	doc, text := decodeTaskXML(t, data)

	for _, want := range []string{"LogonTrigger", "InteractiveToken", "LeastPrivilege", "run --background"} {
		if !strings.Contains(text, want) {
			t.Errorf("xml missing %q", want)
		}
	}
	if doc.UserID != `PC\rizky` {
		t.Errorf("UserId = %q", doc.UserID)
	}
	if doc.Logon != "true" {
		t.Errorf("LogonTrigger Enabled = %q", doc.Logon)
	}
	if doc.LogonType != "InteractiveToken" || doc.RunLevel != "LeastPrivilege" {
		t.Errorf("principal = %q/%q", doc.LogonType, doc.RunLevel)
	}
	if doc.Command != `C:\Remotto\remotto-agent.exe` {
		t.Errorf("Command = %q", doc.Command)
	}
	if doc.Arguments != "run --background" {
		t.Errorf("Arguments = %q", doc.Arguments)
	}
	for _, want := range []string{
		"<DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>",
		"<StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>",
		"<ExecutionTimeLimit>PT0S</ExecutionTimeLimit>",
		"<MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>",
		"<StartWhenAvailable>true</StartWhenAvailable>",
	} {
		if !strings.Contains(text, want) {
			t.Errorf("xml missing %q", want)
		}
	}
}

func TestBuildTaskXMLEscapesSpecialCharacters(t *testing.T) {
	exe := `C:\Program Files\R&D <beta> "x"\remotto-agent.exe`
	user := `DOM&AIN\<user>`
	data, err := BuildTaskXML(exe, user)
	if err != nil {
		t.Fatalf("BuildTaskXML: %v", err)
	}
	doc, text := decodeTaskXML(t, data)

	if doc.Command != exe {
		t.Errorf("Command round trip = %q, want %q", doc.Command, exe)
	}
	if doc.UserID != user {
		t.Errorf("UserId round trip = %q, want %q", doc.UserID, user)
	}
	if !strings.Contains(text, "R&amp;D &lt;beta&gt;") {
		t.Errorf("command not escaped in xml")
	}
}

func TestInstallCallsCreateWithXML(t *testing.T) {
	dir := t.TempDir()
	fr := &fakeRunner{}
	m := &Manager{
		Runner:      fr,
		Executable:  func() (string, error) { return `C:\Program Files\Remotto\remotto-agent.exe`, nil },
		CurrentUser: func() (string, error) { return `PC\rizky`, nil },
		TempDir:     dir,
	}

	if err := m.Install(context.Background()); err != nil {
		t.Fatalf("Install: %v", err)
	}

	if len(fr.calls) != 1 {
		t.Fatalf("calls = %d, want 1", len(fr.calls))
	}
	call := fr.calls[0]
	joined := strings.Join(call, " ")
	for _, want := range []string{"schtasks", "/Create", "/TN", TaskName, "/XML", "/F"} {
		if !strings.Contains(joined, want) {
			t.Errorf("call %q missing %q", joined, want)
		}
	}
	if filepath.Dir(fr.xmlPath) != dir {
		t.Errorf("xml written to %q, want dir %q", fr.xmlPath, dir)
	}
	if len(fr.xmlSeen) == 0 {
		t.Fatalf("xml file not readable during Run")
	}
	doc, _ := decodeTaskXML(t, fr.xmlSeen)
	if doc.Command != `C:\Program Files\Remotto\remotto-agent.exe` {
		t.Errorf("xml Command = %q", doc.Command)
	}

	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 0 {
		t.Errorf("temp files left after Install: %d", len(entries))
	}
}

func TestInstallRemovesTempFileOnFailure(t *testing.T) {
	dir := t.TempDir()
	fr := &fakeRunner{out: []byte("ERROR: boom"), err: errors.New("exit status 1")}
	m := &Manager{
		Runner:      fr,
		Executable:  func() (string, error) { return `C:\remotto-agent.exe`, nil },
		CurrentUser: func() (string, error) { return `PC\rizky`, nil },
		TempDir:     dir,
	}
	if err := m.Install(context.Background()); err == nil {
		t.Fatal("Install succeeded, want error")
	}
	entries, _ := os.ReadDir(dir)
	if len(entries) != 0 {
		t.Errorf("temp files left after failed Install: %d", len(entries))
	}
}

func TestInstallNeedAdmin(t *testing.T) {
	fr := &fakeRunner{
		out: []byte("ERROR: Access is denied."),
		err: errors.New("exit status 1"),
	}
	m := &Manager{
		Runner:      fr,
		Executable:  func() (string, error) { return `C:\remotto-agent.exe`, nil },
		CurrentUser: func() (string, error) { return `PC\rizky`, nil },
		TempDir:     t.TempDir(),
	}
	err := m.Install(context.Background())
	if !errors.Is(err, ErrNeedAdmin) {
		t.Fatalf("err = %v, want ErrNeedAdmin", err)
	}
}

func TestInstallErrorDoesNotLeakOutput(t *testing.T) {
	const raw = "ERROR: secret C:\\Users\\private\\path 0xDEAD"
	fr := &fakeRunner{out: []byte(raw), err: errors.New("exit status 1")}
	m := &Manager{
		Runner:      fr,
		Executable:  func() (string, error) { return `C:\remotto-agent.exe`, nil },
		CurrentUser: func() (string, error) { return `PC\rizky`, nil },
		TempDir:     t.TempDir(),
	}
	err := m.Install(context.Background())
	if !errors.Is(err, ErrInstall) {
		t.Fatalf("err = %v, want ErrInstall", err)
	}
	if strings.Contains(err.Error(), "secret") || strings.Contains(err.Error(), "Users") {
		t.Errorf("error message leaks raw output: %q", err.Error())
	}
}

func TestInstallExecutableError(t *testing.T) {
	fr := &fakeRunner{}
	m := &Manager{
		Runner:      fr,
		Executable:  func() (string, error) { return "", errors.New("no exe") },
		CurrentUser: func() (string, error) { return `PC\rizky`, nil },
		TempDir:     t.TempDir(),
	}
	if err := m.Install(context.Background()); !errors.Is(err, ErrInstall) {
		t.Fatalf("err = %v, want ErrInstall", err)
	}
	if len(fr.calls) != 0 {
		t.Errorf("runner called %d times after resolve failure", len(fr.calls))
	}
}

func TestUninstallCallsDelete(t *testing.T) {
	fr := &fakeRunner{}
	m := &Manager{Runner: fr}
	if err := m.Uninstall(context.Background()); err != nil {
		t.Fatalf("Uninstall: %v", err)
	}
	if len(fr.calls) != 1 {
		t.Fatalf("calls = %d, want 1", len(fr.calls))
	}
	joined := strings.Join(fr.calls[0], " ")
	for _, want := range []string{"/Delete", "/TN", TaskName, "/F"} {
		if !strings.Contains(joined, want) {
			t.Errorf("call %q missing %q", joined, want)
		}
	}
}

func TestUninstallNotFoundIsSuccess(t *testing.T) {
	fr := &fakeRunner{
		out: []byte(`ERROR: The specified task name "\Remotto\Agent" does not exist in the system.`),
		err: errors.New("exit status 1"),
	}
	m := &Manager{Runner: fr}
	if err := m.Uninstall(context.Background()); err != nil {
		t.Fatalf("Uninstall with missing task: %v", err)
	}
}

func TestUninstallFailureDoesNotLeakOutput(t *testing.T) {
	const raw = "ERROR: internal detail 0x80070005"
	fr := &fakeRunner{out: []byte(raw), err: errors.New("exit status 1")}
	m := &Manager{Runner: fr}
	err := m.Uninstall(context.Background())
	if !errors.Is(err, ErrUninstall) {
		t.Fatalf("err = %v, want ErrUninstall", err)
	}
	if strings.Contains(err.Error(), "internal detail") {
		t.Errorf("error message leaks raw output: %q", err.Error())
	}
}

func TestUninstallNeedAdmin(t *testing.T) {
	fr := &fakeRunner{out: []byte("ERROR: Access is denied."), err: errors.New("exit status 1")}
	m := &Manager{Runner: fr}
	if err := m.Uninstall(context.Background()); !errors.Is(err, ErrNeedAdmin) {
		t.Fatalf("err = %v, want ErrNeedAdmin", err)
	}
}

func TestErrorsKeepControlWrapSemantics(t *testing.T) {
	fr := &fakeRunner{err: errors.New("exit status 1")}
	m := &Manager{Runner: fr}
	err := m.Uninstall(context.Background())
	if errors.Is(err, control.ErrUnsupported) {
		t.Errorf("unexpected ErrUnsupported")
	}
	if !errors.Is(err, ErrUninstall) {
		t.Errorf("err = %v, want ErrUninstall", err)
	}
	if !bytes.Contains([]byte(TaskName), []byte(`\`)) {
		t.Errorf("TaskName must include folder separator")
	}
}
