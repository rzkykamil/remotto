package startup

import (
	"bytes"
	"encoding/xml"
	"unicode/utf16"
)

// BuildTaskXML returns the Task Scheduler 1.2 definition of the logon task as
// UTF-16 LE with a byte order mark, the form `schtasks /XML` accepts.
func BuildTaskXML(exePath, userID string) ([]byte, error) {
	var b bytes.Buffer
	b.WriteString(`<?xml version="1.0" encoding="UTF-16"?>` + "\n")
	b.WriteString(`<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">` + "\n")
	b.WriteString("  <Triggers>\n    <LogonTrigger>\n      <Enabled>true</Enabled>\n      <UserId>")
	if err := escapeTo(&b, userID); err != nil {
		return nil, err
	}
	b.WriteString("</UserId>\n    </LogonTrigger>\n  </Triggers>\n")

	b.WriteString("  <Principals>\n    <Principal id=\"Author\">\n      <UserId>")
	if err := escapeTo(&b, userID); err != nil {
		return nil, err
	}
	b.WriteString("</UserId>\n      <LogonType>InteractiveToken</LogonType>\n      <RunLevel>LeastPrivilege</RunLevel>\n    </Principal>\n  </Principals>\n")

	b.WriteString("  <Settings>\n" +
		"    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>\n" +
		"    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>\n" +
		"    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>\n" +
		"    <StartWhenAvailable>true</StartWhenAvailable>\n" +
		"    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>\n" +
		"  </Settings>\n")

	b.WriteString("  <Actions Context=\"Author\">\n    <Exec>\n      <Command>")
	if err := escapeTo(&b, exePath); err != nil {
		return nil, err
	}
	b.WriteString("</Command>\n      <Arguments>run --background</Arguments>\n    </Exec>\n  </Actions>\n")
	b.WriteString("</Task>\n")

	return encodeUTF16LE(b.String()), nil
}

func escapeTo(b *bytes.Buffer, s string) error {
	return xml.EscapeText(b, []byte(s))
}

// encodeUTF16LE writes s as UTF-16 LE, prefixed with a BOM.
func encodeUTF16LE(s string) []byte {
	units := utf16.Encode([]rune(s))
	out := make([]byte, 0, 2+2*len(units))
	out = append(out, 0xFF, 0xFE)
	for _, u := range units {
		out = append(out, byte(u), byte(u>>8))
	}
	return out
}
