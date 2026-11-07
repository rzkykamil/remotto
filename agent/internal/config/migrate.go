package config

import (
	"encoding/json"
	"fmt"
)

// migration upgrades a decoded config document by one schema version. It
// edits doc in place; LoadOrInit sets configVersion after the last step.
type migration func(doc map[string]any) error

// migrations maps a source version to the step that produces source+1.
// It is empty while CurrentVersion is 1. Tests inject steps.
var migrations = map[int]migration{}

// migrate applies the steps from version from up to CurrentVersion, in
// order, and returns the migrated JSON document. A missing step is an error.
func migrate(data []byte, from int) ([]byte, error) {
	var doc map[string]any
	if err := json.Unmarshal(data, &doc); err != nil {
		return nil, fmt.Errorf("parse config for migration: %w", err)
	}
	for v := from; v < CurrentVersion; v++ {
		step, ok := migrations[v]
		if !ok {
			return nil, fmt.Errorf("no migration from configVersion %d", v)
		}
		if err := step(doc); err != nil {
			return nil, fmt.Errorf("migrate configVersion %d to %d: %w", v, v+1, err)
		}
	}
	doc["configVersion"] = CurrentVersion
	out, err := json.Marshal(doc)
	if err != nil {
		return nil, fmt.Errorf("encode migrated config: %w", err)
	}
	return out, nil
}
