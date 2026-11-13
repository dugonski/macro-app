using System;
using System.Linq;
using System.Reflection;
using MacroApp.Sap;
using MacroApp.Ui;

namespace MacroApp
{
    internal static class Program
    {
        private static int Main(string[] args)
        {
            // --simular executa as macros sem o SAP, para testar o app.
            SapGui.Simulate = args.Contains("--simular");
            var version = Assembly.GetExecutingAssembly().GetName().Version.ToString(3);
            try
            {
                new App(version, SapGui.Simulate).Run();
                return 0;
            }
            catch (Exception ex)
            {
                Console.ResetColor();
                Console.Error.WriteLine("erro: " + ex.Message);
                return 1;
            }
        }
    }
}
