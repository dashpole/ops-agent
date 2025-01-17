package main

import (
	"os"
	"testing"
)

func TestDockerfileMatches(t *testing.T) {
	gotDockerfile, err := os.ReadFile(getDockerfilePath())
	if err != nil {
		t.Error(err)
	}
	expectedDockerfile, err := getDockerfile()
	if err != nil {
		t.Error(err)
	}
	if expectedDockerfile != string(gotDockerfile) {
		t.Fatalf("Dockerfile was not generated by ./dockerfiles/compile. Please run `go run ./dockerfiles`")
	}
}
