using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Text;
using System.Threading;
using MacroApp.Macros;

namespace MacroApp.Ui
{
    /// <summary>O terminal do app: lê comandos, recebe a lista e acompanha a execução.</summary>
    internal sealed class App
    {
        private const ConsoleColor Accent = ConsoleColor.DarkYellow;
        private const ConsoleColor Dim = ConsoleColor.DarkGray;
        private const ConsoleColor Good = ConsoleColor.Green;
        private const ConsoleColor Bad = ConsoleColor.Red;
        private const string Spinner = "|/-\\";

        private enum Mode { Idle, Collecting, Running }

        private sealed class Command
        {
            public string Name, Description;
            public Macro Macro;
        }

        private readonly string _version;
        private readonly bool _simulate;
        private readonly Screen _screen = new Screen();
        private readonly List<Command> _commands = new List<Command>();
        private readonly ConcurrentQueue<Action> _fromWorker = new ConcurrentQueue<Action>();
        private readonly Stopwatch _clock = Stopwatch.StartNew();

        private Mode _mode = Mode.Idle;
        private bool _quit, _dirty = true;
        private int _width;

        // caixa de entrada
        private readonly StringBuilder _text = new StringBuilder();
        private int _cursor;
        private int _selected; // sugestão destacada
        private long _lastKeyMs;

        // macro em andamento
        private Macro _active;
        private List<string> _items = new List<string>();
        private CancellationTokenSource _cancel;
        private MacroEvent _current;
        private int _okCount;
        private readonly List<string> _failed = new List<string>();

        public App(string version, bool simulate)
        {
            _version = version;
            _simulate = simulate;
            foreach (var macro in Macro.All)
                _commands.Add(new Command { Name = macro.Command, Description = macro.Description, Macro = macro });
            _commands.Add(new Command { Name = "ajuda", Description = "Mostra os comandos disponíveis" });
            _commands.Add(new Command { Name = "limpar", Description = "Limpa a tela" });
            _commands.Add(new Command { Name = "sair", Description = "Fecha o app" });
        }

        public void Run()
        {
            Console.OutputEncoding = new UTF8Encoding(false);
            Console.TreatControlCAsInput = true;
            try { Console.Title = "Macro App"; } catch (Exception) { }
            PrintBanner();

            while (!_quit)
            {
                Action fromWorker;
                while (_fromWorker.TryDequeue(out fromWorker)) { fromWorker(); _dirty = true; }

                while (!_quit && Console.KeyAvailable)
                {
                    var previous = _lastKeyMs;
                    _lastKeyMs = _clock.ElapsedMilliseconds;
                    OnKey(Console.ReadKey(true), _lastKeyMs - previous);
                    _dirty = true;
                }

                if (_mode == Mode.Running || _width != _screen.Width) _dirty = true;
                if (_dirty && !_quit) Render();
                Thread.Sleep(_mode == Mode.Running ? 80 : 20);
            }

            if (_cancel != null) _cancel.Cancel();
            _screen.Leave();
        }

        private void PrintBanner()
        {
            const string hint = "Digite / para ver os comandos · /ajuda para ajuda";
            var title = new Line().Add("│ ", Accent).Add("* Macro App", Accent).Add("  v" + _version, Dim);
            var used = 14 + _version.Length;
            if (_simulate) { title.Add("  [simulação]", Bad); used += 13; }
            title.Add(new string(' ', hint.Length - used) + " │", Accent);

            var bar = new string('─', hint.Length + 2);
            _screen.Print(
                new Line("┌" + bar + "┐", Accent),
                title,
                new Line().Add("│ ", Accent).Add(hint, Dim).Add(" │", Accent),
                new Line("└" + bar + "┘", Accent),
                new Line());
        }

        // ---- teclado ----

        private void OnKey(ConsoleKeyInfo key, long sincePreviousMs)
        {
            if (key.Key == ConsoleKey.C && (key.Modifiers & ConsoleModifiers.Control) != 0)
            {
                _quit = true;
                return;
            }
            switch (_mode)
            {
                case Mode.Running:
                    if (key.Key == ConsoleKey.Escape && _cancel != null) _cancel.Cancel();
                    break;
                case Mode.Collecting:
                    OnKeyCollecting(key, sincePreviousMs);
                    break;
                default:
                    OnKeyIdle(key);
                    break;
            }
        }

        private void OnKeyIdle(ConsoleKeyInfo key)
        {
            var suggestions = Suggestions();
            var pick = suggestions.Count == 0 ? null : suggestions[Math.Min(_selected, suggestions.Count - 1)];
            switch (key.Key)
            {
                case ConsoleKey.UpArrow:
                    if (pick != null) _selected = (_selected + suggestions.Count - 1) % suggestions.Count;
                    return;
                case ConsoleKey.DownArrow:
                    if (pick != null) _selected = (_selected + 1) % suggestions.Count;
                    return;
                case ConsoleKey.Tab:
                    if (pick != null) SetText("/" + pick.Name + " ");
                    return;
                case ConsoleKey.Escape:
                    SetText("");
                    return;
                case ConsoleKey.Enter:
                    var text = pick != null ? "/" + pick.Name : _text.ToString().Trim();
                    SetText("");
                    if (text.Length > 0) Execute(text);
                    return;
            }
            if (EditText(key)) _selected = 0;
        }

        private void OnKeyCollecting(ConsoleKeyInfo key, long sincePreviousMs)
        {
            switch (key.Key)
            {
                case ConsoleKey.Escape:
                    Reset();
                    _screen.Print(new Line("  Cancelado.", Dim), new Line());
                    return;
                case ConsoleKey.Enter:
                    var text = _text.ToString().Trim();
                    SetText("");
                    if (text.Length > 0)
                        AddItems(text);
                    // Linha em branco no meio de uma colagem não deve disparar a macro.
                    else if (_items.Count > 0 && sincePreviousMs >= 150)
                        Start();
                    return;
            }
            EditText(key);
        }

        /// <summary>Edição básica da linha. Devolve true se o texto mudou.</summary>
        private bool EditText(ConsoleKeyInfo key)
        {
            switch (key.Key)
            {
                case ConsoleKey.LeftArrow: _cursor = Math.Max(0, _cursor - 1); return false;
                case ConsoleKey.RightArrow: _cursor = Math.Min(_text.Length, _cursor + 1); return false;
                case ConsoleKey.Home: _cursor = 0; return false;
                case ConsoleKey.End: _cursor = _text.Length; return false;
                case ConsoleKey.Backspace:
                    if (_cursor == 0) return false;
                    _text.Remove(--_cursor, 1);
                    return true;
                case ConsoleKey.Delete:
                    if (_cursor >= _text.Length) return false;
                    _text.Remove(_cursor, 1);
                    return true;
            }
            if (key.KeyChar == '\0' || char.IsControl(key.KeyChar)) return false;
            _text.Insert(_cursor++, key.KeyChar);
            return true;
        }

        private void SetText(string text)
        {
            _text.Clear().Append(text);
            _cursor = text.Length;
            _selected = 0;
        }

        // ---- comandos ----

        private List<Command> Suggestions()
        {
            var text = _text.ToString();
            if (_mode != Mode.Idle || !text.StartsWith("/") || text.Any(char.IsWhiteSpace))
                return new List<Command>();
            var prefix = text.Substring(1).ToLowerInvariant();
            return _commands.Where(c => c.Name.StartsWith(prefix)).ToList();
        }

        private void Execute(string text)
        {
            _screen.Print(new Line().Add("> ", Accent).Add(text));
            var parts = text.Split((char[])null, 2, StringSplitOptions.RemoveEmptyEntries);
            if (!parts[0].StartsWith("/"))
            {
                _screen.Print(new Line("  Os comandos começam com /. Digite /ajuda para ver a lista.", Dim), new Line());
                return;
            }

            var name = parts[0].Substring(1).ToLowerInvariant();
            var command = _commands.FirstOrDefault(c => c.Name == name);
            if (command == null)
            {
                _screen.Print(new Line().Add("  Comando desconhecido: " + parts[0], Bad).Add(" · /ajuda mostra a lista", Dim), new Line());
            }
            else if (command.Macro != null)
            {
                _active = command.Macro;
                _mode = Mode.Collecting;
                if (parts.Length > 1) AddItems(parts[1]);
                if (_items.Count > 0) Start();
            }
            else if (name == "ajuda")
            {
                foreach (var c in _commands)
                    _screen.Print(new Line().Add("  /" + c.Name.PadRight(8), Accent).Add("  " + c.Description));
                _screen.Print(new Line(), new Line("  Dica: a lista pode ir junto do comando, ex.: /pdfs 12345 67890", Dim), new Line());
            }
            else if (name == "limpar")
            {
                _screen.Clear();
                PrintBanner();
            }
            else if (name == "sair")
            {
                _quit = true;
            }
        }

        /// <summary>Separa por espaço, vírgula, ponto e vírgula ou quebra de linha, sem repetir.</summary>
        private void AddItems(string text)
        {
            var separators = new[] { ' ', '\t', '\r', '\n', ',', ';' };
            foreach (var item in text.Split(separators, StringSplitOptions.RemoveEmptyEntries))
                if (!_items.Contains(item)) _items.Add(item);
        }

        // ---- execução ----

        private void Start()
        {
            _mode = Mode.Running;
            _cancel = new CancellationTokenSource();
            _current = null;
            SetText("");
            _screen.Print(new Line().Add("  " + _active.Title).Add(" · " + _items.Count + " " + _active.ItemLabel, Dim));

            var macro = _active;
            var items = _items.ToArray();
            var cancel = _cancel.Token;
            var worker = new Thread(() =>
            {
                Exception error = null;
                try { macro.Run(items, e => _fromWorker.Enqueue(() => OnEvent(e)), cancel); }
                catch (Exception ex) { error = ex; }
                _fromWorker.Enqueue(() => OnDone(error));
            });
            worker.IsBackground = true;
            worker.TrySetApartmentState(ApartmentState.STA); // exigido pelo COM do SAP
            worker.Start();
        }

        private void OnEvent(MacroEvent e)
        {
            switch (e.Kind)
            {
                case EventKind.Progress:
                    _current = e;
                    break;
                case EventKind.Ok:
                    _okCount++;
                    _screen.Print(new Line().Add("  √ ", Good).Add(e.Item).Add("  " + e.Text, Dim));
                    break;
                case EventKind.Fail:
                    _failed.Add(e.Item);
                    _screen.Print(new Line().Add("  × ", Bad).Add(e.Item).Add("  " + e.Text, Bad));
                    break;
                default:
                    _screen.Print(new Line("  " + e.Text, Dim));
                    break;
            }
        }

        private void OnDone(Exception error)
        {
            var total = _items.Count;
            if (error is OperationCanceledException)
                _screen.Print(new Line("  Cancelado · " + _okCount + " abertos de " + total, Dim));
            else if (error != null)
                _screen.Print(new Line("  × " + error.Message, Bad));
            else if (_failed.Count == 0)
                _screen.Print(new Line("  Concluído · " + _okCount + " de " + total + " abertos", Good));
            else
                _screen.Print(
                    new Line().Add("  Concluído · ").Add(_okCount + " abertos", Good).Add(" · ").Add(_failed.Count + " com falha", Bad),
                    new Line("  Falharam: " + string.Join(", ", _failed), Dim));
            _screen.Print(new Line());
            Reset();
        }

        private void Reset()
        {
            _mode = Mode.Idle;
            _active = null;
            _items = new List<string>();
            _cancel = null;
            _current = null;
            _okCount = 0;
            _failed.Clear();
            SetText("");
        }

        // ---- tela ----

        private void Render()
        {
            _dirty = false;
            _width = _screen.Width;
            var lines = new List<Line>();

            if (_mode == Mode.Running)
            {
                var frame = Spinner[(int)(_clock.ElapsedMilliseconds / 100 % Spinner.Length)].ToString();
                var status = _current == null
                    ? "Conectando ao SAP..."
                    : "Processando " + _current.Index + "/" + _current.Total + " · " + _current.Item;
                lines.Add(new Line().Add("  " + frame + " ", Accent).Add(status).Add("   Esc para cancelar", Dim));
                _screen.Render(lines, -1, 0);
                return;
            }

            var collecting = _mode == Mode.Collecting;
            if (collecting)
                lines.Add(new Line().Add("  " + _active.Title).Add(" · " + _items.Count + " " + _active.ItemLabel + " na lista", Dim));

            // caixa de entrada: mostra o trecho do texto em volta do cursor
            var border = collecting ? Accent : Dim;
            var inner = _width - 4;
            var room = inner - 2;
            var start = Math.Max(0, _cursor - room + 1);
            var shown = _text.ToString(start, Math.Min(room, _text.Length - start));
            var inputRow = lines.Count + 1;
            lines.Add(new Line("┌" + new string('─', inner + 2) + "┐", border));
            lines.Add(new Line().Add("│ ", border).Add(collecting ? "+ " : "> ", Accent)
                .Add(shown.PadRight(room)).Add(" │", border));
            lines.Add(new Line("└" + new string('─', inner + 2) + "┘", border));

            var suggestions = Suggestions();
            if (collecting)
                lines.Add(new Line(_items.Count > 0
                    ? "  Enter com a linha vazia executa · Esc cancela"
                    : "  Cole ou digite os " + _active.ItemLabel + " e tecle Enter · Esc cancela", Dim));
            else if (suggestions.Count == 0)
                lines.Add(new Line("  / para comandos · Ctrl+C para sair", Dim));
            for (var i = 0; i < suggestions.Count; i++)
            {
                var name = "  /" + suggestions[i].Name.PadRight(8) + "  ";
                lines.Add(i == Math.Min(_selected, suggestions.Count - 1)
                    ? new Line().Add(name, Accent).Add(suggestions[i].Description)
                    : new Line(name + suggestions[i].Description, Dim));
            }

            _screen.Render(lines, inputRow, 4 + _cursor - start);
        }
    }
}
