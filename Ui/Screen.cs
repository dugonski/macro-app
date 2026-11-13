using System;
using System.Collections.Generic;

namespace MacroApp.Ui
{
    /// <summary>Uma linha de texto com trechos coloridos.</summary>
    internal sealed class Line
    {
        public readonly List<KeyValuePair<string, ConsoleColor?>> Parts = new List<KeyValuePair<string, ConsoleColor?>>();

        public Line() { }
        public Line(string text, ConsoleColor? color = null) { Add(text, color); }

        public Line Add(string text, ConsoleColor? color = null)
        {
            Parts.Add(new KeyValuePair<string, ConsoleColor?>(text, color));
            return this;
        }
    }

    /// <summary>
    /// Console dividido em duas partes: o histórico, que rola normalmente, e uma
    /// área viva no fim (caixa de entrada, sugestões, progresso) que é redesenhada.
    /// </summary>
    internal sealed class Screen
    {
        private int _top = -1; // primeira linha da área viva
        private int _height;   // linhas ocupadas pela área viva

        /// <summary>Largura útil: uma coluna a menos para o console nunca quebrar a linha sozinho.</summary>
        public int Width { get { return Math.Max(24, Console.WindowWidth) - 1; } }

        /// <summary>Escreve linhas no histórico, acima da área viva.</summary>
        public void Print(params Line[] lines)
        {
            try
            {
                Console.CursorVisible = false;
                if (_top < 0) _top = Console.CursorTop;
                for (var i = 0; i < _height; i++) ClearRow(_top + i);
                Console.SetCursorPosition(0, _top);
            }
            catch (ArgumentOutOfRangeException) { }

            foreach (var line in lines)
            {
                Write(line, 0);
                Console.WriteLine();
            }
            _top = Console.CursorTop;
            _height = 0;
        }

        /// <summary>Redesenha a área viva. cursorRow negativo esconde o cursor.</summary>
        public void Render(IList<Line> lines, int cursorRow, int cursorCol)
        {
            try
            {
                Console.CursorVisible = false;
                if (_top < 0) _top = Console.CursorTop;

                // Sem espaço abaixo: rola o console para abrir.
                var overflow = _top + lines.Count - Console.BufferHeight;
                if (overflow > 0)
                {
                    Console.SetCursorPosition(0, Console.BufferHeight - 1);
                    for (var i = 0; i < overflow; i++) Console.WriteLine();
                    _top = Math.Max(0, _top - overflow);
                }

                var width = Width;
                for (var i = 0; i < lines.Count; i++)
                {
                    Console.SetCursorPosition(0, _top + i);
                    Write(lines[i], width);
                }
                for (var i = lines.Count; i < _height; i++) ClearRow(_top + i);
                _height = lines.Count;

                if (cursorRow >= 0)
                {
                    Console.SetCursorPosition(Math.Min(cursorCol, width), _top + cursorRow);
                    Console.CursorVisible = true;
                }
            }
            catch (ArgumentOutOfRangeException)
            {
                // A janela mudou de tamanho no meio do desenho: recomeça de onde o cursor está.
                _top = -1;
                _height = 0;
            }
        }

        public void Clear()
        {
            Console.Clear();
            _top = -1;
            _height = 0;
        }

        /// <summary>Deixa o cursor depois da área viva, para o app sair limpo.</summary>
        public void Leave()
        {
            Render(new Line[0], -1, 0);
            Console.CursorVisible = true;
        }

        private void ClearRow(int row)
        {
            if (row >= Console.BufferHeight) return;
            Console.SetCursorPosition(0, row);
            Console.Write(new string(' ', Width));
        }

        // padTo > 0 corta e completa a linha com espaços até essa largura.
        private static void Write(Line line, int padTo)
        {
            var written = 0;
            foreach (var part in line.Parts)
            {
                var text = part.Key;
                if (padTo > 0 && written + text.Length > padTo) text = text.Substring(0, padTo - written);
                if (text.Length == 0) continue;
                if (part.Value.HasValue) Console.ForegroundColor = part.Value.Value;
                Console.Write(text);
                Console.ResetColor();
                written += text.Length;
            }
            if (padTo > written) Console.Write(new string(' ', padTo - written));
        }
    }
}
