//go:build !windows

package sap

import "errors"

func run(func(Session) error) error {
	return errors.New("o SAP GUI só está disponível no Windows (use --simular para testar)")
}
