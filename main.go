package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/dugonski/macro-app/internal/sap"
	"github.com/dugonski/macro-app/internal/ui"
)

var version = "0.1.0"

func main() {
	simular := flag.Bool("simular", false, "executa as macros sem o SAP, para testar o app")
	flag.Parse()
	sap.Simulate = *simular

	if err := ui.Run(version, *simular); err != nil {
		fmt.Fprintln(os.Stderr, "erro:", err)
		os.Exit(1)
	}
}
