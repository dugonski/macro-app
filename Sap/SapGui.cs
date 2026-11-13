using System;
using System.Reflection;
using System.Runtime.InteropServices;

namespace MacroApp.Sap
{
    /// <summary>Conecta na sessão aberta do SAP GUI via SAP GUI Scripting.</summary>
    public static class SapGui
    {
        private const string NotRunning = "SAP não encontrado: abra o SAP e faça login antes de executar";

        /// <summary>Troca o SAP real por uma sessão falsa (para testar o app sem SAP).</summary>
        public static bool Simulate;

        /// <summary>Executa a ação com a sessão ativa. Deve ser chamado de uma thread STA.</summary>
        public static void Run(Action<ISapSession> action)
        {
            if (Simulate)
            {
                action(new FakeSession());
                return;
            }
            if (Environment.OSVersion.Platform != PlatformID.Win32NT)
                throw new SapException("o SAP GUI só está disponível no Windows (use --simular para testar)");

            action(new ComSession(Connect()));
        }

        // Equivale a GetObject("SAPGUI").GetScriptingEngine.Children(0).Children(0) do VBA.
        private static object Connect()
        {
            object gui;
            try { gui = Marshal.BindToMoniker("SAPGUI"); }
            catch (Exception) { throw new SapException(NotRunning); }

            object engine;
            try { engine = Com.Call(gui, "GetScriptingEngine"); }
            catch (Exception) { engine = null; }
            if (engine == null)
                throw new SapException("SAP GUI Scripting indisponível: verifique se o scripting está habilitado");

            try
            {
                var connection = Com.Call(engine, "Children", 0);
                var session = Com.Call(connection, "Children", 0);
                if (session != null) return session;
            }
            catch (Exception) { }
            throw new SapException(NotRunning);
        }

        private sealed class ComSession : ISapSession
        {
            private readonly object _session;

            public ComSession(object session) { _session = session; }

            private object Find(string id)
            {
                object element;
                try { element = Com.Call(_session, "findById", id); }
                catch (Exception) { element = null; }
                if (element == null)
                    throw new SapException("elemento \"" + id + "\" não encontrado na tela do SAP");
                return element;
            }

            public void SetText(string id, string text) { Com.Set(Find(id), "Text", text); }
            public void SendVKey(string window, int key) { Com.Call(Find(window), "sendVKey", key); }
            public void Press(string id) { Com.Call(Find(id), "press"); }
            public void PressButton(string id, string button) { Com.Call(Find(id), "pressButton", button); }
            public void Maximize(string window) { Com.Call(Find(window), "maximize"); }

            public void StatusBar(out string type, out string text)
            {
                var bar = Find("wnd[0]/sbar");
                type = Convert.ToString(Com.Call(bar, "MessageType"));
                text = Convert.ToString(Com.Call(bar, "Text"));
            }
        }

        /// <summary>Chamadas por nome (IDispatch), como o VBA faz.</summary>
        private static class Com
        {
            public static object Call(object target, string name, params object[] args)
            {
                return Invoke(target, name, BindingFlags.InvokeMethod | BindingFlags.GetProperty, args);
            }

            public static void Set(object target, string name, object value)
            {
                Invoke(target, name, BindingFlags.SetProperty, new[] { value });
            }

            private static object Invoke(object target, string name, BindingFlags flags, object[] args)
            {
                try
                {
                    return target.GetType().InvokeMember(name, flags, null, target, args);
                }
                catch (TargetInvocationException ex) when (ex.InnerException != null)
                {
                    throw new SapException(name + " falhou: " + ex.InnerException.Message);
                }
            }
        }
    }
}
