//go:build windows

package sap

import (
	"fmt"
	"runtime"
	"unsafe"

	"github.com/go-ole/go-ole"
	"github.com/go-ole/go-ole/oleutil"
)

type comSession struct{ session *ole.IDispatch }

func run(fn func(Session) error) error {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()

	if err := ole.CoInitializeEx(0, ole.COINIT_APARTMENTTHREADED); err != nil {
		// S_FALSE (1) = COM já inicializado nesta thread; não é erro.
		if oleErr, ok := err.(*ole.OleError); !ok || oleErr.Code() != 1 {
			return fmt.Errorf("falha ao iniciar o COM: %w", err)
		}
	}
	defer ole.CoUninitialize()

	session, err := connect()
	if err != nil {
		return err
	}
	defer session.Release()
	return fn(&comSession{session})
}

// connect equivale a GetObject("SAPGUI").GetScriptingEngine.Children(0).Children(0).
func connect() (*ole.IDispatch, error) {
	gui, err := sapGUI()
	if err != nil {
		return nil, ErrNotRunning
	}
	defer gui.Release()

	engine, err := oleutil.CallMethod(gui, "GetScriptingEngine")
	if err != nil || engine.ToIDispatch() == nil {
		return nil, fmt.Errorf("SAP GUI Scripting indisponível (verifique se o scripting está habilitado): %v", err)
	}
	app := engine.ToIDispatch()
	defer app.Release()

	conn, err := firstChild(app)
	if err != nil {
		return nil, ErrNotRunning
	}
	defer conn.Release()

	session, err := firstChild(conn)
	if err != nil {
		return nil, ErrNotRunning
	}
	return session, nil
}

func sapGUI() (*ole.IDispatch, error) {
	if unk, err := ole.GetObject("SAPGUI", nil, ole.IID_IDispatch); err == nil && unk != nil {
		return (*ole.IDispatch)(unsafe.Pointer(unk)), nil
	}
	// Alternativa: wrapper da ROT instalado junto com o SAP GUI.
	unk, err := oleutil.CreateObject("SapROTWr.SapROTWrapper")
	if err != nil {
		return nil, err
	}
	defer unk.Release()
	wrapper, err := unk.QueryInterface(ole.IID_IDispatch)
	if err != nil {
		return nil, err
	}
	defer wrapper.Release()
	entry, err := oleutil.CallMethod(wrapper, "GetROTEntry", "SAPGUI")
	if err != nil {
		return nil, err
	}
	if entry.ToIDispatch() == nil {
		return nil, ErrNotRunning
	}
	return entry.ToIDispatch(), nil
}

func firstChild(parent *ole.IDispatch) (*ole.IDispatch, error) {
	children, err := oleutil.GetProperty(parent, "Children")
	if err != nil || children.ToIDispatch() == nil {
		return nil, fmt.Errorf("sem acesso a Children: %v", err)
	}
	coll := children.ToIDispatch()
	defer coll.Release()

	child, err := oleutil.CallMethod(coll, "ElementAt", int32(0))
	if err != nil || child.ToIDispatch() == nil {
		return nil, fmt.Errorf("nenhum item em Children: %v", err)
	}
	return child.ToIDispatch(), nil
}

func (s *comSession) find(id string) (*ole.IDispatch, error) {
	v, err := oleutil.CallMethod(s.session, "findById", id)
	if err != nil {
		return nil, fmt.Errorf("elemento %q não encontrado na tela do SAP", id)
	}
	if v.ToIDispatch() == nil {
		return nil, fmt.Errorf("elemento %q não encontrado na tela do SAP", id)
	}
	return v.ToIDispatch(), nil
}

func (s *comSession) call(id, method string, args ...interface{}) error {
	obj, err := s.find(id)
	if err != nil {
		return err
	}
	defer obj.Release()
	if _, err := oleutil.CallMethod(obj, method, args...); err != nil {
		return fmt.Errorf("%s em %q falhou: %w", method, id, err)
	}
	return nil
}

func (s *comSession) SetText(id, text string) error {
	obj, err := s.find(id)
	if err != nil {
		return err
	}
	defer obj.Release()
	if _, err := oleutil.PutProperty(obj, "Text", text); err != nil {
		return fmt.Errorf("não foi possível preencher %q: %w", id, err)
	}
	return nil
}

func (s *comSession) SendVKey(window string, key int) error {
	return s.call(window, "sendVKey", int32(key))
}

func (s *comSession) Press(id string) error { return s.call(id, "press") }

func (s *comSession) PressButton(id, button string) error {
	return s.call(id, "pressButton", button)
}

func (s *comSession) Maximize(window string) error { return s.call(window, "maximize") }

func (s *comSession) StatusBar() (string, string, error) {
	bar, err := s.find("wnd[0]/sbar")
	if err != nil {
		return "", "", err
	}
	defer bar.Release()
	msgType, err := oleutil.GetProperty(bar, "MessageType")
	if err != nil {
		return "", "", err
	}
	text, err := oleutil.GetProperty(bar, "Text")
	if err != nil {
		return "", "", err
	}
	return msgType.ToString(), text.ToString(), nil
}
