#:package Markdig@1.2.0
#:package DocumentFormat.OpenXml@3.5.1

using System.Globalization;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Validation;
using DocumentFormat.OpenXml.Wordprocessing;
using Markdig;
using Markdig.Extensions.AutoIdentifiers;
using Markdig.Extensions.Alerts;
using Markdig.Extensions.DefinitionLists;
using Markdig.Extensions.Footnotes;
using Markdig.Extensions.TaskLists;
using Markdig.Extensions.Yaml;
using Markdig.Renderers.Html;
using Markdig.Syntax;
using Markdig.Syntax.Inlines;
using A = DocumentFormat.OpenXml.Drawing;
using Pic = DocumentFormat.OpenXml.Drawing.Pictures;
using Wp = DocumentFormat.OpenXml.Drawing.Wordprocessing;
using MdFootnote = Markdig.Extensions.Footnotes.Footnote;
using WFootnote = DocumentFormat.OpenXml.Wordprocessing.Footnote;
using MdTable = Markdig.Extensions.Tables.Table;
using MdTableRow = Markdig.Extensions.Tables.TableRow;
using MdTableCell = Markdig.Extensions.Tables.TableCell;
using MdAlign = Markdig.Extensions.Tables.TableColumnAlign;

return Cli.Run(args);

static class Cli
{
    const string Usage = """
        usage: dotnet run md2docx.cs -- <input.md> [output.docx] [options]

        Converts GitHub-flavored Markdown to a Word document.

        options:
          --page letter|a4      page size (default: letter)
          --image-root DIR      only embed local images under DIR (default: the input file's directory)
          --strict              exit 3 if any warning was raised (the file is still written)
          -h, --help            show this help

        exit codes: 0 ok, 1 bad usage or unreadable input, 2 conversion or validation failure, 3 warnings under --strict
        """;

    public static int Run(string[] args)
    {
        string? input = null, output = null, imageRoot = null;
        var page = "letter";
        var strict = false;

        for (var i = 0; i < args.Length; i++)
        {
            var a = args[i];
            switch (a)
            {
                case "-h" or "--help":
                    Console.WriteLine(Usage);
                    return 0;
                case "--strict":
                    strict = true;
                    break;
                case "--page" or "--image-root":
                    if (i + 1 >= args.Length) return Fail($"{a} requires a value");
                    if (a == "--page") page = args[++i].ToLowerInvariant();
                    else imageRoot = args[++i];
                    break;
                default:
                    if (a.StartsWith("--", StringComparison.Ordinal)) return Fail($"unknown option {a}");
                    if (input is null) input = a;
                    else if (output is null) output = a;
                    else return Fail($"unexpected argument {a}");
                    break;
            }
        }

        if (input is null) return Fail("missing input file");
        if (page is not ("letter" or "a4")) return Fail($"--page must be letter or a4, got '{page}'");

        input = Path.GetFullPath(input);
        if (!File.Exists(input)) return Fail($"input file not found: {input}");
        output = Path.GetFullPath(output ?? Path.ChangeExtension(input, ".docx"));
        if (!output.EndsWith(".docx", StringComparison.OrdinalIgnoreCase)) return Fail($"output must end in .docx: {output}");
        if (string.Equals(input, output, StringComparison.Ordinal)) return Fail("output path is the same as the input path");

        string markdown;
        try { markdown = File.ReadAllText(input, new UTF8Encoding(false)); }
        catch (Exception ex) { return Fail($"cannot read {input}: {ex.Message}"); }

        var baseDir = Path.GetDirectoryName(input)!;
        var root = Path.GetFullPath(imageRoot ?? baseDir);
        var temp = output + ".tmp-" + Guid.NewGuid().ToString("N")[..8];
        ConvertResult result;
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(output)!);
            result = new Converter(baseDir, root, page == "a4").Convert(markdown, temp);
            if (result.ValidationErrors.Count > 0)
            {
                foreach (var e in result.ValidationErrors) Console.Error.WriteLine($"error: invalid docx structure: {e}");
                return Fail("the generated document failed OpenXML schema validation; not writing the output", 2);
            }
            File.Move(temp, output, overwrite: true);
        }
        catch (Exception ex)
        {
            return Fail($"conversion failed: {ex.GetType().Name}: {ex.Message}", 2);
        }
        finally
        {
            try { if (File.Exists(temp)) File.Delete(temp); } catch { /* best effort */ }
        }

        Console.WriteLine($"Wrote {output} ({result.Paragraphs} paragraphs, {result.Tables} tables, {result.Images} images, {result.Footnotes} footnotes)");
        foreach (var w in result.Warnings) Console.Error.WriteLine($"warning: {w}");
        return strict && result.Warnings.Count > 0 ? 3 : 0;
    }

    static int Fail(string message, int code = 1)
    {
        Console.Error.WriteLine($"error: {message}");
        if (code == 1) Console.Error.WriteLine("run with --help for usage");
        return code;
    }
}

sealed record ConvertResult(int Paragraphs, int Tables, int Images, int Footnotes, List<string> Warnings, List<string> ValidationErrors);

sealed record RunFormat
{
    public static readonly RunFormat Plain = new();
    public bool Bold { get; init; }
    public bool Italic { get; init; }
    public bool Strike { get; init; }
    public bool Underline { get; init; }
    public bool Sub { get; init; }
    public bool Super { get; init; }
    public bool Mark { get; init; }
    public bool Code { get; init; }
    public string? Href { get; init; }
    public string? Anchor { get; init; }
    public string? Tooltip { get; init; }
    public string? Color { get; init; }
    public bool IsLink => Href is not null || Anchor is not null;
}

sealed record Ctx
{
    public int ListDepth { get; init; } = -1;
    public int ListAfter { get; init; } = 60;
    public int QuoteDepth { get; init; }
    public string QuoteColor { get; init; } = "D0D7DE";
    public int ExtraLeft { get; init; }
    public string? BaseStyle { get; init; }
    public RunFormat BaseFormat { get; init; } = RunFormat.Plain;
    public JustificationValues? Align { get; init; }
    public bool InFootnote { get; init; }
    public bool InTable { get; init; }
    public long? ImageBudgetEmu { get; init; }
    public const int MaxLeft = 5400;
    public int Left => Math.Min((ListDepth >= 0 ? 720 * (ListDepth + 1) : 0) + 360 * QuoteDepth + ExtraLeft, MaxLeft);
}

sealed record ListMark(int NumId, int Level);

sealed class HtmlState
{
    public bool Bold, Italic, Underline, Strike, Sub, Super, Code, Mark;
    public string? Href, Anchor;

    public RunFormat Overlay(RunFormat f) => f with
    {
        Bold = f.Bold || Bold,
        Italic = f.Italic || Italic,
        Underline = f.Underline || Underline,
        Strike = f.Strike || Strike,
        Sub = f.Sub || Sub,
        Super = f.Super || Super,
        Code = f.Code || Code,
        Mark = f.Mark || Mark,
        Href = f.Href ?? Href,
        Anchor = f.Anchor ?? Anchor,
    };
}

sealed record HtmlTag(string Name, bool Closing, bool SelfClosing, Dictionary<string, string> Attrs)
{
    static readonly Regex TagRx = new(@"^<\s*(/?)\s*([A-Za-z][A-Za-z0-9-]*)(.*?)(/?)\s*>$", RegexOptions.Singleline | RegexOptions.Compiled);
    static readonly Regex AttrRx = new(@"([A-Za-z_:][\w:.-]*)\s*(?:=\s*(?:""([^""]*)""|'([^']*)'|([^\s""'>]+)))?", RegexOptions.Compiled);

    public static HtmlTag? Parse(string raw)
    {
        var m = TagRx.Match(raw.Trim());
        if (!m.Success) return null;
        var attrs = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (Match am in AttrRx.Matches(m.Groups[3].Value))
        {
            var v = am.Groups[2].Success ? am.Groups[2].Value : am.Groups[3].Success ? am.Groups[3].Value : am.Groups[4].Value;
            attrs[am.Groups[1].Value] = WebUtility.HtmlDecode(v);
        }
        return new HtmlTag(m.Groups[2].Value.ToLowerInvariant(), m.Groups[1].Value == "/", m.Groups[4].Value == "/", attrs);
    }
}

readonly record struct ImageInfo(string ContentType, int Width, int Height);

static class ImageProbe
{
    public static ImageInfo? Probe(byte[] d)
    {
        if (d.Length >= 24 && d[0] == 0x89 && d[1] == 'P' && d[2] == 'N' && d[3] == 'G')
            return new ImageInfo("png", (d[16] << 24) | (d[17] << 16) | (d[18] << 8) | d[19], (d[20] << 24) | (d[21] << 16) | (d[22] << 8) | d[23]);
        if (d.Length >= 10 && d[0] == 'G' && d[1] == 'I' && d[2] == 'F')
            return new ImageInfo("gif", d[6] | (d[7] << 8), d[8] | (d[9] << 8));
        if (d.Length >= 26 && d[0] == 'B' && d[1] == 'M')
            return new ImageInfo("bmp", BitConverter.ToInt32(d, 18), Math.Abs(BitConverter.ToInt32(d, 22)));
        if (d.Length >= 4 && d[0] == 0xFF && d[1] == 0xD8)
        {
            var i = 2;
            while (i + 9 < d.Length)
            {
                if (d[i] != 0xFF) { i++; continue; }
                var marker = d[i + 1];
                if (marker == 0xFF) { i++; continue; }
                if (marker is 0xD8 or 0x01 || marker is >= 0xD0 and <= 0xD7) { i += 2; continue; }
                var len = (d[i + 2] << 8) | d[i + 3];
                if (marker is >= 0xC0 and <= 0xCF && marker is not (0xC4 or 0xC8 or 0xCC))
                    return new ImageInfo("jpeg", (d[i + 7] << 8) | d[i + 8], (d[i + 5] << 8) | d[i + 6]);
                i += 2 + len;
            }
        }
        return null;
    }
}

sealed class Converter
{
    const int TwipEmu = 635;
    const int Margin = 1440;
    const string MonoFont = "Consolas";

    static readonly MarkdownPipeline Pipeline = new MarkdownPipelineBuilder()
        .UseYamlFrontMatter()
        .UsePipeTables()
        .UseGridTables()
        .UseEmphasisExtras()
        .UseAutoLinks()
        .UseTaskLists()
        .UseFootnotes()
        .UseDefinitionLists()
        .UseListExtras()
        .UseAlertBlocks()
        .UseAutoIdentifiers(AutoIdentifierOptions.GitHub)
        .Build();

    static readonly HashSet<string> BlockTags = new(StringComparer.Ordinal)
    {
        "p", "div", "section", "article", "header", "footer", "main", "aside", "nav", "ul", "ol", "dl", "dt", "dd", "tr", "table",
        "thead", "tbody", "tfoot", "blockquote", "details", "summary", "center", "figure", "figcaption", "li",
        "h1", "h2", "h3", "h4", "h5", "h6",
    };

    static readonly Regex HtmlTokenRx = new(@"<!--.*?-->|</?[A-Za-z][^>]*>|[^<]+|<", RegexOptions.Singleline | RegexOptions.Compiled);
    static readonly HashSet<string> SafeSchemes = new(StringComparer.OrdinalIgnoreCase) { "http", "https", "mailto", "tel", "ftp", "ftps" };

    readonly string _baseDir;
    readonly string _imageRoot;
    readonly int _pageW, _pageH, _contentW;
    readonly List<string> _warnings = [];
    readonly HashSet<string> _warned = [];
    readonly Dictionary<string, string> _anchors = new(StringComparer.Ordinal);
    readonly HashSet<string> _usedBookmarkNames = new(StringComparer.OrdinalIgnoreCase);
    readonly Dictionary<string, string> _hyperlinkIds = new(StringComparer.Ordinal);
    readonly Dictionary<string, (string RelId, ImageInfo Info)> _imageParts = new(StringComparer.Ordinal);
    readonly List<AbstractNum> _abstractNums = [];
    readonly List<NumberingInstance> _nums = [];
    readonly Dictionary<string, int> _abstractIds = new(StringComparer.Ordinal);

    MainDocumentPart _main = null!;
    FootnotesPart? _footnotesPart;
    uint _bookmarkId = 1;
    uint _drawingId = 1;
    int _nextFootnoteId = 1;
    Run? _lastTextRun;
    RunFormat? _lastTextFormat;

    public Converter(string baseDir, string imageRoot, bool a4)
    {
        _baseDir = baseDir;
        _imageRoot = imageRoot;
        (_pageW, _pageH) = a4 ? (11906, 16838) : (12240, 15840);
        _contentW = _pageW - 2 * Margin;
    }

    public ConvertResult Convert(string markdown, string outPath)
    {
        var mdDoc = Markdown.Parse(markdown, Pipeline);
        CollectAnchors(mdDoc);

        int paragraphs, tables, images;
        var footnotes = 0;
        using (var doc = WordprocessingDocument.Create(outPath, WordprocessingDocumentType.Document))
        {
            _main = doc.AddMainDocumentPart();
            var body = new Body();
            _main.Document = new Document(body);
            AddStyles();

            var blocks = new List<OpenXmlElement>();
            RenderBlocks(mdDoc, new Ctx(), blocks);
            if (blocks.Count == 0) blocks.Add(new Paragraph());
            foreach (var b in blocks) body.Append(b);
            body.Append(new SectionProperties(
                new PageSize { Width = (uint)_pageW, Height = (uint)_pageH },
                new PageMargin { Top = Margin, Right = (uint)Margin, Bottom = Margin, Left = (uint)Margin, Header = 720, Footer = 720, Gutter = 0 }));

            FinishNumbering();
            FinishSettings();
            SetProperties(doc, mdDoc);

            paragraphs = body.Descendants<Paragraph>().Count();
            tables = body.Descendants<Table>().Count();
            images = body.Descendants<Drawing>().Count();
            if (_footnotesPart is not null) footnotes = _nextFootnoteId - 1;
            _main.Document.Save();
        }

        return new ConvertResult(paragraphs, tables, images, footnotes, _warnings, Validate(outPath));
    }

    static List<string> Validate(string path)
    {
        using var doc = WordprocessingDocument.Open(path, false);
        return new OpenXmlValidator(FileFormatVersions.Office2019)
            .Validate(doc)
            .Select(e => $"{e.Description} (at {e.Path?.XPath})")
            .Take(20)
            .ToList();
    }

    void Warn(string message)
    {
        if (_warned.Add(message)) _warnings.Add(message);
    }

    // ── document scaffolding ────────────────────────────────────────────────

    void SetProperties(WordprocessingDocument doc, MarkdownDocument md)
    {
        string? title = null;
        if (md.FirstOrDefault() is YamlFrontMatterBlock fm)
        {
            var m = Regex.Match(fm.Lines.ToString(), @"^\s*title\s*:\s*(.+?)\s*$", RegexOptions.Multiline);
            if (m.Success) title = m.Groups[1].Value.Trim('"', '\'');
        }
        title ??= md.Descendants<HeadingBlock>().FirstOrDefault(h => h.Level == 1) is { Inline: { } inl } ? PlainText(inl) : null;
        if (!string.IsNullOrWhiteSpace(title)) doc.PackageProperties.Title = Clean(title);
        doc.PackageProperties.Created = DateTime.UtcNow;
        doc.PackageProperties.Modified = DateTime.UtcNow;
    }

    void FinishSettings()
    {
        var part = _main.AddNewPart<DocumentSettingsPart>();
        var settings = new Settings();
        if (_footnotesPart is not null)
            settings.Append(new FootnoteDocumentWideProperties(new FootnoteSpecialReference { Id = -1 }, new FootnoteSpecialReference { Id = 0 }));
        settings.Append(new Compatibility(new CompatibilitySetting
        {
            Name = CompatSettingNameValues.CompatibilityMode,
            Uri = "http://schemas.microsoft.com/office/word",
            Val = "15",
        }));
        part.Settings = settings;
    }

    void FinishNumbering()
    {
        if (_abstractNums.Count == 0) return;
        var part = _main.AddNewPart<NumberingDefinitionsPart>();
        var numbering = new Numbering();
        foreach (var a in _abstractNums) numbering.Append(a);
        foreach (var n in _nums) numbering.Append(n);
        part.Numbering = numbering;
    }

    void AddStyles()
    {
        var part = _main.AddNewPart<StyleDefinitionsPart>();
        var styles = new Styles(new DocDefaults(
            new RunPropertiesDefault(new RunPropertiesBaseStyle(
                new RunFonts { Ascii = "Calibri", HighAnsi = "Calibri", ComplexScript = "Calibri" },
                new FontSize { Val = "22" }, new FontSizeComplexScript { Val = "22" },
                new Languages { Val = "en-US" })),
            new ParagraphPropertiesDefault(new ParagraphPropertiesBaseStyle(
                new SpacingBetweenLines { After = "120", Line = "264", LineRule = LineSpacingRuleValues.Auto }))));

        styles.Append(new Style(new StyleName { Val = "Normal" }, new PrimaryStyle())
        { Type = StyleValues.Paragraph, Default = true, StyleId = "Normal" });
        styles.Append(new Style(new StyleName { Val = "Default Paragraph Font" }, new UIPriority { Val = 1 }, new SemiHidden(), new UnhideWhenUsed())
        { Type = StyleValues.Character, Default = true, StyleId = "DefaultParagraphFont" });
        styles.Append(new Style(new StyleName { Val = "Normal Table" }, new UIPriority { Val = 99 }, new SemiHidden(), new UnhideWhenUsed(),
            new StyleTableProperties(new TableIndentation { Width = 0, Type = TableWidthUnitValues.Dxa },
                new TableCellMarginDefault(
                    new TopMargin { Width = "0", Type = TableWidthUnitValues.Dxa },
                    new TableCellLeftMargin { Width = 108, Type = TableWidthValues.Dxa },
                    new BottomMargin { Width = "0", Type = TableWidthUnitValues.Dxa },
                    new TableCellRightMargin { Width = 108, Type = TableWidthValues.Dxa })))
        { Type = StyleValues.Table, Default = true, StyleId = "TableNormal" });
        styles.Append(new Style(new StyleName { Val = "No List" }, new UIPriority { Val = 99 }, new SemiHidden(), new UnhideWhenUsed())
        { Type = StyleValues.Numbering, Default = true, StyleId = "NoList" });

        var headings = new (int Size, bool Rule, string Color, bool Italic)[]
        {
            (40, true, "1F2328", false), (32, true, "1F2328", false), (26, false, "1F2328", false),
            (24, false, "1F2328", false), (22, false, "1F2328", false), (22, false, "656D76", true),
        };
        for (var i = 0; i < headings.Length; i++)
        {
            var h = headings[i];
            var ppr = new StyleParagraphProperties(
                new KeepNext(), new KeepLines(),
                new SpacingBetweenLines { Before = i == 0 ? "360" : "280", After = "120" },
                new OutlineLevel { Val = i });
            if (h.Rule)
                ppr.ParagraphBorders = new ParagraphBorders(new BottomBorder { Val = BorderValues.Single, Size = 4, Space = 4, Color = "D0D7DE" });
            var rpr = new StyleRunProperties(new Bold(), new Color { Val = h.Color }, new FontSize { Val = h.Size.ToString() }, new FontSizeComplexScript { Val = h.Size.ToString() });
            if (h.Italic) rpr.Italic = new Italic();
            styles.Append(new Style(new StyleName { Val = $"heading {i + 1}" }, new BasedOn { Val = "Normal" }, new NextParagraphStyle { Val = "Normal" },
                new UIPriority { Val = 9 }, new PrimaryStyle(), ppr, rpr)
            { Type = StyleValues.Paragraph, StyleId = $"Heading{i + 1}" });
        }

        styles.Append(new Style(new StyleName { Val = "Block Quote" }, new BasedOn { Val = "Normal" }, new PrimaryStyle(),
            new StyleRunProperties(new Color { Val = "57606A" }))
        { Type = StyleValues.Paragraph, StyleId = "BlockQuote" });

        styles.Append(new Style(new StyleName { Val = "Code Block" }, new BasedOn { Val = "Normal" }, new PrimaryStyle(),
            new StyleParagraphProperties(
                new ParagraphBorders(
                    new TopBorder { Val = BorderValues.Single, Size = 4, Space = 4, Color = "D0D7DE" },
                    new LeftBorder { Val = BorderValues.Single, Size = 4, Space = 6, Color = "D0D7DE" },
                    new BottomBorder { Val = BorderValues.Single, Size = 4, Space = 4, Color = "D0D7DE" },
                    new RightBorder { Val = BorderValues.Single, Size = 4, Space = 6, Color = "D0D7DE" }),
                new Shading { Val = ShadingPatternValues.Clear, Color = "auto", Fill = "F6F8FA" },
                new SpacingBetweenLines { Before = "0", After = "0", Line = "240", LineRule = LineSpacingRuleValues.Auto }),
            new StyleRunProperties(new RunFonts { Ascii = MonoFont, HighAnsi = MonoFont, ComplexScript = MonoFont, EastAsia = MonoFont },
                new FontSize { Val = "19" }, new FontSizeComplexScript { Val = "19" }))
        { Type = StyleValues.Paragraph, StyleId = "CodeBlock" });

        styles.Append(new Style(new StyleName { Val = "Code Char" }, new BasedOn { Val = "DefaultParagraphFont" }, new PrimaryStyle(),
            new StyleRunProperties(new RunFonts { Ascii = MonoFont, HighAnsi = MonoFont, ComplexScript = MonoFont, EastAsia = MonoFont },
                new FontSize { Val = "20" }, new FontSizeComplexScript { Val = "20" },
                new Shading { Val = ShadingPatternValues.Clear, Color = "auto", Fill = "EFF1F3" }))
        { Type = StyleValues.Character, StyleId = "CodeChar" });

        styles.Append(new Style(new StyleName { Val = "Hyperlink" }, new BasedOn { Val = "DefaultParagraphFont" }, new UIPriority { Val = 99 }, new UnhideWhenUsed(),
            new StyleRunProperties(new Color { Val = "0563C1" }, new Underline { Val = UnderlineValues.Single }))
        { Type = StyleValues.Character, StyleId = "Hyperlink" });

        styles.Append(new Style(new StyleName { Val = "Table Text" }, new BasedOn { Val = "Normal" }, new PrimaryStyle(),
            new StyleParagraphProperties(new SpacingBetweenLines { Before = "0", After = "0", Line = "252", LineRule = LineSpacingRuleValues.Auto }),
            new StyleRunProperties(new FontSize { Val = "20" }, new FontSizeComplexScript { Val = "20" }))
        { Type = StyleValues.Paragraph, StyleId = "TableText" });

        styles.Append(new Style(new StyleName { Val = "footnote text" }, new BasedOn { Val = "Normal" }, new UIPriority { Val = 99 }, new UnhideWhenUsed(),
            new StyleParagraphProperties(new SpacingBetweenLines { After = "40", Line = "240", LineRule = LineSpacingRuleValues.Auto }),
            new StyleRunProperties(new FontSize { Val = "20" }, new FontSizeComplexScript { Val = "20" }))
        { Type = StyleValues.Paragraph, StyleId = "FootnoteText" });

        styles.Append(new Style(new StyleName { Val = "footnote reference" }, new BasedOn { Val = "DefaultParagraphFont" }, new UIPriority { Val = 99 }, new UnhideWhenUsed(),
            new StyleRunProperties(new VerticalTextAlignment { Val = VerticalPositionValues.Superscript }))
        { Type = StyleValues.Character, StyleId = "FootnoteReference" });

        part.Styles = styles;
    }

    // ── numbering ───────────────────────────────────────────────────────────

    int GetAbstract(string key, NumberFormatValues format, string delimiter)
    {
        if (_abstractIds.TryGetValue(key, out var existing)) return existing;
        var id = _abstractNums.Count;
        var abs = new AbstractNum(new MultiLevelType { Val = MultiLevelValues.HybridMultilevel }) { AbstractNumberId = id };
        for (var lvl = 0; lvl < 9; lvl++)
        {
            var isBullet = format == NumberFormatValues.Bullet;
            var text = isBullet ? new[] { "\u2022", "\u25E6", "\u25AA" }[lvl % 3] : $"%{lvl + 1}{delimiter}";
            abs.Append(new Level(
                new StartNumberingValue { Val = 1 },
                new NumberingFormat { Val = format },
                new LevelText { Val = text },
                new LevelJustification { Val = LevelJustificationValues.Left },
                new PreviousParagraphProperties(new Indentation { Left = (720 * (lvl + 1)).ToString(), Hanging = "360" }))
            { LevelIndex = lvl });
        }
        _abstractNums.Add(abs);
        _abstractIds[key] = id;
        return id;
    }

    int NewNum(int abstractId, int level, int? start)
    {
        var numId = _nums.Count + 1;
        var inst = new NumberingInstance(new AbstractNumId { Val = abstractId }) { NumberID = numId };
        if (start is { } s)
            inst.Append(new LevelOverride(new StartOverrideNumberingValue { Val = s }) { LevelIndex = level });
        _nums.Add(inst);
        return numId;
    }

    static (NumberFormatValues Format, string Key) OrderedFormat(char bulletType) => bulletType switch
    {
        'a' => (NumberFormatValues.LowerLetter, "lowerLetter"),
        'A' => (NumberFormatValues.UpperLetter, "upperLetter"),
        'i' => (NumberFormatValues.LowerRoman, "lowerRoman"),
        'I' => (NumberFormatValues.UpperRoman, "upperRoman"),
        _ => (NumberFormatValues.Decimal, "decimal"),
    };

    static int ParseOrderedStart(ListBlock list)
    {
        var s = list.OrderedStart;
        if (string.IsNullOrEmpty(s)) return 1;
        if (int.TryParse(s, NumberStyles.None, CultureInfo.InvariantCulture, out var n)) return Math.Max(n, 0);
        if (list.BulletType is 'a' or 'A' && s.Length == 1 && char.IsAsciiLetter(s[0]))
            return char.ToLowerInvariant(s[0]) - 'a' + 1;
        var roman = ParseRoman(s);
        return roman > 0 ? roman : 1;
    }

    static int ParseRoman(string s)
    {
        var map = new Dictionary<char, int> { ['i'] = 1, ['v'] = 5, ['x'] = 10, ['l'] = 50, ['c'] = 100, ['d'] = 500, ['m'] = 1000 };
        var total = 0;
        for (var i = 0; i < s.Length; i++)
        {
            if (!map.TryGetValue(char.ToLowerInvariant(s[i]), out var v)) return 0;
            total += i + 1 < s.Length && map.TryGetValue(char.ToLowerInvariant(s[i + 1]), out var next) && next > v ? -v : v;
        }
        return total;
    }

    // ── text helpers ────────────────────────────────────────────────────────

    // XmlWriter throws on characters XML 1.0 forbids (stray control chars and lone surrogates are common in pasted text).
    static string Clean(string s)
    {
        StringBuilder? sb = null;
        for (var i = 0; i < s.Length; i++)
        {
            var ch = s[i];
            var ok = ch is '\t' or '\n' or '\r' || (ch >= 0x20 && ch <= 0xD7FF) || (ch >= 0xE000 && ch <= 0xFFFD);
            if (!ok && char.IsHighSurrogate(ch) && i + 1 < s.Length && char.IsLowSurrogate(s[i + 1]))
            {
                sb?.Append(ch).Append(s[i + 1]);
                i++;
                continue;
            }
            if (ok) { sb?.Append(ch); continue; }
            sb ??= new StringBuilder(s, 0, i, s.Length);
            sb.Append('\uFFFD');
        }
        return sb?.ToString() ?? s;
    }

    static string PlainText(ContainerInline? c)
    {
        if (c is null) return string.Empty;
        var sb = new StringBuilder();
        for (var i = c.FirstChild; i is not null; i = i.NextSibling)
        {
            switch (i)
            {
                case LiteralInline l: sb.Append(l.Content.ToString()); break;
                case CodeInline code: sb.Append(code.Content); break;
                case HtmlEntityInline e: sb.Append(e.Transcoded.ToString()); break;
                case LineBreakInline: sb.Append(' '); break;
                case ContainerInline ci: sb.Append(PlainText(ci)); break;
            }
        }
        return sb.ToString();
    }

    static string PlainText(Block b) => b switch
    {
        LeafBlock { Inline: { } inl } => PlainText(inl),
        LeafBlock leaf => leaf.Lines.ToString(),
        ContainerBlock cb => string.Join(" ", cb.Select(PlainText)),
        _ => string.Empty,
    };

    static string ExpandTabs(string line)
    {
        if (!line.Contains('\t')) return line;
        var sb = new StringBuilder();
        foreach (var ch in line)
        {
            if (ch == '\t') sb.Append(' ', 4 - sb.Length % 4);
            else sb.Append(ch);
        }
        return sb.ToString();
    }

    // ── anchors ─────────────────────────────────────────────────────────────

    void CollectAnchors(MarkdownDocument md)
    {
        foreach (var h in md.Descendants<HeadingBlock>())
        {
            var id = h.GetAttributes().Id;
            if (string.IsNullOrEmpty(id) || _anchors.ContainsKey(id)) continue;
            // Word bookmark names allow only letters, digits and underscore, max 40 chars.
            var name = "_" + Regex.Replace(id, "[^A-Za-z0-9_]", "_");
            if (name.Length > 36) name = name[..36];
            var candidate = name;
            for (var n = 2; !_usedBookmarkNames.Add(candidate); n++) candidate = $"{name}_{n}";
            _anchors[id] = candidate;
        }
    }

    // ── block rendering ─────────────────────────────────────────────────────

    void RenderBlocks(ContainerBlock container, Ctx c, List<OpenXmlElement> sink)
    {
        foreach (var block in container) RenderBlock(block, c, sink);
    }

    void RenderBlock(Block block, Ctx c, List<OpenXmlElement> sink)
    {
        switch (block)
        {
            case YamlFrontMatterBlock or LinkReferenceDefinitionGroup or LinkReferenceDefinition or FootnoteGroup or EmptyBlock:
                return;
            case HeadingBlock h:
                RenderHeading(h, c, sink);
                return;
            case ParagraphBlock pb:
                sink.Add(BuildParagraph(pb, c, null));
                return;
            case CodeBlock cb:
                RenderCode(cb.Lines.ToString().Replace("\r\n", "\n").Split('\n'), c, sink);
                return;
            case AlertBlock alert:
                RenderAlert(alert, c, sink);
                return;
            case QuoteBlock q:
                RenderBlocks(q, c with { QuoteDepth = c.QuoteDepth + 1 }, sink);
                return;
            case ListBlock l:
                RenderList(l, c, sink);
                return;
            case ThematicBreakBlock:
                sink.Add(ThematicBreak(c));
                return;
            case MdTable t:
                RenderTable(t, c, sink);
                return;
            case DefinitionList dl:
                RenderDefinitionList(dl, c, sink);
                return;
            case HtmlBlock hb:
                RenderHtml(hb.Lines.ToString(), c, sink);
                return;
            case ContainerBlock container:
                Warn($"unsupported block '{block.GetType().Name}'; rendered its content as plain blocks");
                RenderBlocks(container, c, sink);
                return;
            case LeafBlock { Inline: { } inl }:
                Warn($"unsupported block '{block.GetType().Name}'; rendered its content as a paragraph");
                var p = NewParagraph(c, null);
                AppendInlines(p, inl, c.BaseFormat, c);
                sink.Add(p);
                return;
            case LeafBlock leaf:
                Warn($"unsupported block '{block.GetType().Name}'; rendered its text as a paragraph");
                var lp = NewParagraph(c, null);
                AddText(lp, Clean(leaf.Lines.ToString()), c.BaseFormat);
                sink.Add(lp);
                return;
        }
    }

    Paragraph NewParagraph(Ctx c, string? style, ListMark? mark = null, bool hanging = false, bool listContinuation = false)
    {
        var pPr = new ParagraphProperties();
        style ??= c.BaseStyle ?? (c.QuoteDepth > 0 ? "BlockQuote" : null);
        if (style is not null) pPr.ParagraphStyleId = new ParagraphStyleId { Val = style };
        if (c.QuoteDepth > 0 && style != "CodeBlock")
            pPr.ParagraphBorders = new ParagraphBorders(new LeftBorder { Val = BorderValues.Single, Size = 18, Space = 10, Color = c.QuoteColor });
        if (mark is not null)
            pPr.NumberingProperties = new NumberingProperties(new NumberingLevelReference { Val = mark.Level }, new NumberingId { Val = mark.NumId });
        if (c.ListDepth >= 0 && (mark is not null || hanging || listContinuation))
            pPr.SpacingBetweenLines = new SpacingBetweenLines { After = c.ListAfter.ToString() };
        if (mark is not null || hanging)
            pPr.Indentation = new Indentation { Left = c.Left.ToString(), Hanging = "360" };
        else if (c.Left > 0)
            pPr.Indentation = new Indentation { Left = c.Left.ToString() };
        if (c.Align is { } align) pPr.Justification = new Justification { Val = align };
        return pPr.HasChildren ? new Paragraph(pPr) : new Paragraph();
    }

    static ParagraphProperties Props(Paragraph p) => p.ParagraphProperties ??= new ParagraphProperties();

    Paragraph BuildParagraph(ParagraphBlock pb, Ctx c, ListMark? mark)
    {
        var isTask = pb.Inline?.FirstChild is TaskList;
        var p = NewParagraph(c, null, isTask ? null : mark, hanging: isTask, listContinuation: mark is null && c.ListDepth >= 0);
        AppendInlines(p, pb.Inline, c.BaseFormat, c);
        return p;
    }

    void RenderHeading(HeadingBlock h, Ctx c, List<OpenXmlElement> sink)
    {
        var p = NewParagraph(c, $"Heading{Math.Clamp(h.Level, 1, 6)}");
        var id = h.GetAttributes().Id;
        var bookmarkId = _bookmarkId++;
        var hasAnchor = id is not null && _anchors.ContainsKey(id);
        if (hasAnchor) p.Append(new BookmarkStart { Id = bookmarkId.ToString(), Name = _anchors[id!] });
        AppendInlines(p, h.Inline, c.BaseFormat, c);
        if (hasAnchor) p.Append(new BookmarkEnd { Id = bookmarkId.ToString() });
        sink.Add(p);
    }

    void RenderCode(string[] lines, Ctx c, List<OpenXmlElement> sink)
    {
        if (sink.Count > 0 && sink[^1] is Paragraph { ParagraphProperties.ParagraphStyleId.Val.Value: "CodeBlock" })
            sink.Add(new Paragraph(new ParagraphProperties(new SpacingBetweenLines { Before = "0", After = "0", Line = "160", LineRule = LineSpacingRuleValues.Exact })));
        var count = lines.Length;
        while (count > 0 && string.IsNullOrWhiteSpace(lines[count - 1])) count--;
        if (count == 0) count = 1;
        for (var i = 0; i < count; i++)
        {
            var p = NewParagraph(c, "CodeBlock");
            var text = i < lines.Length ? Clean(ExpandTabs(lines[i])) : string.Empty;
            if (text.Length > 0) p.Append(new Run(new Text(text) { Space = SpaceProcessingModeValues.Preserve }));
            if (i == count - 1) SetSpacingAfter(p, 160);
            sink.Add(p);
        }
    }

    void RenderAlert(AlertBlock alert, Ctx c, List<OpenXmlElement> sink)
    {
        var kind = alert.Kind.ToString().Trim().ToUpperInvariant();
        var (label, color) = kind switch
        {
            "NOTE" => ("Note", "0969DA"),
            "TIP" => ("Tip", "1A7F37"),
            "IMPORTANT" => ("Important", "8250DF"),
            "WARNING" => ("Warning", "9A6700"),
            "CAUTION" => ("Caution", "CF222E"),
            _ => (System.Globalization.CultureInfo.InvariantCulture.TextInfo.ToTitleCase(kind.ToLowerInvariant()), "656D76"),
        };
        var ac = c with { QuoteDepth = c.QuoteDepth + 1, QuoteColor = color };
        var title = NewParagraph(ac, null);
        title.Append(new Run(new RunProperties { Bold = new Bold(), Color = new Color { Val = color } }, new Text(label) { Space = SpaceProcessingModeValues.Preserve }));
        sink.Add(title);
        RenderBlocks(alert, ac, sink);
    }

    Paragraph ThematicBreak(Ctx c)
    {
        var p = NewParagraph(c, null);
        Props(p).ParagraphBorders = new ParagraphBorders(new BottomBorder { Val = BorderValues.Single, Size = 6, Space = 1, Color = "C0C4C8" });
        Props(p).SpacingBetweenLines = new SpacingBetweenLines { Before = "120", After = "120" };
        return p;
    }

    static void SetSpacingAfter(Paragraph p, int after)
    {
        var pPr = Props(p);
        pPr.SpacingBetweenLines ??= new SpacingBetweenLines();
        pPr.SpacingBetweenLines.After = after.ToString();
    }

    void RenderList(ListBlock list, Ctx c, List<OpenXmlElement> sink)
    {
        var depth = c.ListDepth + 1;
        var level = Math.Min(depth, 8);
        int abs, numId;
        if (list.IsOrdered)
        {
            var (format, fmtKey) = OrderedFormat(list.BulletType);
            var delim = list.OrderedDelimiter == ')' ? ")" : ".";
            abs = GetAbstract($"{fmtKey}|{delim}", format, delim);
            numId = NewNum(abs, level, ParseOrderedStart(list));
        }
        else
        {
            abs = GetAbstract("bullet", NumberFormatValues.Bullet, string.Empty);
            numId = NewNum(abs, level, null);
        }

        var lc = c with { ListDepth = depth, ListAfter = list.IsLoose ? 120 : 60 };
        var mark = new ListMark(numId, level);
        foreach (var block in list)
        {
            if (block is ListItemBlock item) RenderListItem(item, lc, mark, sink);
            else RenderBlock(block, lc, sink);
        }
        if (c.ListDepth < 0 && sink.Count > 0 && sink[^1] is Paragraph last) SetSpacingAfter(last, 120);
    }

    void RenderListItem(ListItemBlock item, Ctx c, ListMark mark, List<OpenXmlElement> sink)
    {
        var markUsed = false;
        foreach (var child in item)
        {
            if (!markUsed)
            {
                markUsed = true;
                if (child is ParagraphBlock pb)
                {
                    sink.Add(BuildParagraph(pb, c, mark));
                    continue;
                }
                sink.Add(NewParagraph(c, null, mark));
            }
            RenderBlock(child, c, sink);
        }
        if (!markUsed) sink.Add(NewParagraph(c, null, mark));
    }

    void RenderDefinitionList(DefinitionList dl, Ctx c, List<OpenXmlElement> sink)
    {
        foreach (var item in dl.OfType<DefinitionItem>())
        {
            foreach (var child in item)
            {
                if (child is DefinitionTerm term)
                {
                    var p = NewParagraph(c, null);
                    Props(p).KeepNext = new KeepNext();
                    Props(p).SpacingBetweenLines = new SpacingBetweenLines { After = "40" };
                    AppendInlines(p, term.Inline, c.BaseFormat with { Bold = true }, c);
                    sink.Add(p);
                }
                else
                {
                    RenderBlock(child, c with { ExtraLeft = c.ExtraLeft + 720 }, sink);
                }
            }
        }
    }

    // ── tables ──────────────────────────────────────────────────────────────

    void RenderTable(MdTable t, Ctx c, List<OpenXmlElement> sink)
    {
        var rows = t.OfType<MdTableRow>().ToList();
        var cols = t.ColumnDefinitions?.Count ?? 0;
        foreach (var r in rows)
            cols = Math.Max(cols, r.OfType<MdTableCell>().Sum(x => Math.Max(1, x.ColumnSpan)));
        if (cols == 0 || rows.Count == 0) return;

        var avail = Math.Max(_contentW - c.Left, 1440);
        var widths = ComputeColumnWidths(rows, cols, avail);

        var tbl = new Table();
        tbl.Append(new TableProperties
        {
            TableWidth = new TableWidth { Width = widths.Sum().ToString(), Type = TableWidthUnitValues.Dxa },
            TableIndentation = new TableIndentation { Width = c.Left, Type = TableWidthUnitValues.Dxa },
            TableBorders = new TableBorders(
                new TopBorder { Val = BorderValues.Single, Size = 4, Color = "BFC5CC", Space = 0 },
                new LeftBorder { Val = BorderValues.Single, Size = 4, Color = "BFC5CC", Space = 0 },
                new BottomBorder { Val = BorderValues.Single, Size = 4, Color = "BFC5CC", Space = 0 },
                new RightBorder { Val = BorderValues.Single, Size = 4, Color = "BFC5CC", Space = 0 },
                new InsideHorizontalBorder { Val = BorderValues.Single, Size = 4, Color = "BFC5CC", Space = 0 },
                new InsideVerticalBorder { Val = BorderValues.Single, Size = 4, Color = "BFC5CC", Space = 0 }),
            TableLayout = new TableLayout { Type = TableLayoutValues.Fixed },
            TableCellMarginDefault = new TableCellMarginDefault(
                new TopMargin { Width = "50", Type = TableWidthUnitValues.Dxa },
                new TableCellLeftMargin { Width = 100, Type = TableWidthValues.Dxa },
                new BottomMargin { Width = "50", Type = TableWidthUnitValues.Dxa },
                new TableCellRightMargin { Width = 100, Type = TableWidthValues.Dxa }),
        });
        var grid = new TableGrid();
        foreach (var w in widths) grid.Append(new GridColumn { Width = w.ToString() });
        tbl.Append(grid);

        var carryRemaining = new int[cols];
        var carrySpan = new int[cols];
        foreach (var row in rows)
        {
            var tr = new TableRow();
            var trPr = new TableRowProperties(new CantSplit());
            if (row.IsHeader) trPr.Append(new TableHeader());
            tr.Append(trPr);

            var cells = row.OfType<MdTableCell>().ToList();
            var ci = 0;
            var col = 0;
            while (col < cols)
            {
                if (carryRemaining[col] > 0)
                {
                    var span = Math.Clamp(carrySpan[col], 1, cols - col);
                    var cont = NewCell(widths, col, span);
                    cont.TableCellProperties!.VerticalMerge = new VerticalMerge();
                    cont.Append(new Paragraph());
                    tr.Append(cont);
                    carryRemaining[col]--;
                    col += span;
                    continue;
                }
                if (ci >= cells.Count)
                {
                    var filler = NewCell(widths, col, 1);
                    filler.Append(new Paragraph());
                    tr.Append(filler);
                    col++;
                    continue;
                }

                var cell = cells[ci++];
                var cellSpan = Math.Clamp(cell.ColumnSpan, 1, cols - col);
                var tc = NewCell(widths, col, cellSpan);
                var colWidth = 0;
                for (var k = 0; k < cellSpan; k++) colWidth += widths[col + k];
                if (row.IsHeader) tc.TableCellProperties!.Shading = new Shading { Val = ShadingPatternValues.Clear, Color = "auto", Fill = "F0F3F6" };
                if (cell.RowSpan > 1)
                {
                    tc.TableCellProperties!.VerticalMerge = new VerticalMerge { Val = MergedCellValues.Restart };
                    carryRemaining[col] = cell.RowSpan - 1;
                    carrySpan[col] = cellSpan;
                }

                var alignDef = t.ColumnDefinitions is { } defs && col < defs.Count ? defs[col].Alignment : null;
                var cellCtx = new Ctx
                {
                    BaseStyle = "TableText",
                    InTable = true,
                    BaseFormat = row.IsHeader ? RunFormat.Plain with { Bold = true } : RunFormat.Plain,
                    Align = alignDef switch { MdAlign.Center => JustificationValues.Center, MdAlign.Right => JustificationValues.Right, _ => null },
                    ImageBudgetEmu = Math.Max(colWidth - 200, 360) * (long)TwipEmu,
                };
                var content = new List<OpenXmlElement>();
                RenderBlocks(cell, cellCtx, content);
                if (content.Count == 0 || content[^1] is not Paragraph) content.Add(new Paragraph());
                foreach (var e in content) tc.Append(e);
                tr.Append(tc);
                col += cellSpan;
            }
            tbl.Append(tr);
        }

        sink.Add(tbl);
        // Word merges adjacent tables and needs a paragraph after a table (also mandatory as a cell's last child).
        var spacer = new Paragraph(new ParagraphProperties(new SpacingBetweenLines { After = "80", Line = "120", LineRule = LineSpacingRuleValues.Exact }));
        sink.Add(spacer);
    }

    static TableCell NewCell(int[] widths, int col, int span)
    {
        var width = 0;
        for (var k = 0; k < span && col + k < widths.Length; k++) width += widths[col + k];
        var props = new TableCellProperties { TableCellWidth = new TableCellWidth { Width = width.ToString(), Type = TableWidthUnitValues.Dxa } };
        if (span > 1) props.GridSpan = new GridSpan { Val = span };
        return new TableCell(props);
    }

    static int[] ComputeColumnWidths(List<MdTableRow> rows, int cols, int avail)
    {
        const double CharTwips = 118, Pad = 280, Floor = 640;
        var maxLen = new double[cols];
        var longestWord = new double[cols];
        foreach (var row in rows)
        {
            var col = 0;
            foreach (var cell in row.OfType<MdTableCell>())
            {
                if (col >= cols) break;
                if (cell.ColumnSpan <= 1)
                {
                    var text = PlainText(cell);
                    maxLen[col] = Math.Max(maxLen[col], text.Length);
                    foreach (var word in text.Split(' ', StringSplitOptions.RemoveEmptyEntries))
                        longestWord[col] = Math.Max(longestWord[col], word.Length);
                }
                col += Math.Max(1, cell.ColumnSpan);
            }
        }

        // min: wide enough that the longest word doesn't split mid-word; pref: wide enough for the whole cell on one line.
        var min = new double[cols];
        var pref = new double[cols];
        for (var i = 0; i < cols; i++)
        {
            min[i] = Math.Max(Floor, Math.Min(longestWord[i], 30) * CharTwips + Pad);
            pref[i] = Math.Max(min[i], Math.Min(maxLen[i], 45) * CharTwips + Pad);
        }

        double sumMin = min.Sum(), sumPref = pref.Sum();
        var w = new double[cols];
        for (var i = 0; i < cols; i++)
        {
            w[i] = sumPref <= avail ? pref[i] * avail / sumPref
                : sumMin >= avail ? min[i] * avail / sumMin
                : min[i] + (pref[i] - min[i]) * (avail - sumMin) / (sumPref - sumMin);
        }

        var widths = w.Select(x => (int)Math.Floor(x)).ToArray();
        widths[Array.IndexOf(widths, widths.Max())] += avail - widths.Sum();
        return widths;
    }

    // ── inlines ─────────────────────────────────────────────────────────────

    void AppendInlines(Paragraph p, ContainerInline? container, RunFormat format, Ctx c)
    {
        var elements = new List<OpenXmlElement>();
        _lastTextRun = null;
        AppendInlines(elements, container, format, c);
        _lastTextRun = null;
        foreach (var e in elements) p.Append(e);
    }

    void AppendInlines(List<OpenXmlElement> sink, ContainerInline? container, RunFormat format, Ctx c)
    {
        if (container is null) return;
        var html = new HtmlState();
        for (var inline = container.FirstChild; inline is not null; inline = inline.NextSibling)
        {
            var f = html.Overlay(format);
            switch (inline)
            {
                case LiteralInline lit:
                    AddText(sink, Clean(lit.Content.ToString()), f);
                    break;
                case HtmlEntityInline ent:
                    AddText(sink, Clean(ent.Transcoded.ToString()), f);
                    break;
                case CodeInline code:
                    AddText(sink, Clean(code.Content), f with { Code = true });
                    break;
                case LineBreakInline lb:
                    if (lb.IsHard)
                    {
                        var br = new Run();
                        if (RunProps(f) is { } brProps) br.Append(brProps);
                        br.Append(new Break());
                        sink.Add(WrapLink(br, f));
                        _lastTextRun = null;
                    }
                    else AddText(sink, " ", f);
                    break;
                case EmphasisInline em:
                    AppendInlines(sink, em, ApplyEmphasis(em, f), c);
                    break;
                case LinkInline { IsImage: true } img:
                    AddImage(sink, img.Url, PlainText(img), f, c);
                    break;
                case LinkInline link:
                    AppendLink(sink, link, f, c);
                    break;
                case AutolinkInline auto:
                    {
                        var url = auto.IsEmail && !auto.Url.StartsWith("mailto:", StringComparison.OrdinalIgnoreCase) ? "mailto:" + auto.Url : auto.Url;
                        AddText(sink, Clean(auto.Url), ResolveLink(url, null, f));
                        break;
                    }
                case HtmlInline hi:
                    HandleInlineHtml(sink, html, hi.Tag, f, c);
                    break;
                case TaskList task when inline.PreviousSibling is null:
                    sink.Add(new Run(
                        new RunProperties(new RunFonts { Ascii = "MS Gothic", HighAnsi = "MS Gothic", EastAsia = "MS Gothic" }),
                        new Text(task.Checked ? "\u2612" : "\u2610") { Space = SpaceProcessingModeValues.Preserve },
                        new TabChar()));
                    break;
                case TaskList misplaced:
                    AddText(sink, misplaced.Checked ? "[x]" : "[ ]", f);
                    break;
                case FootnoteLink fl:
                    if (fl.IsBackLink) break;
                    if (c.InFootnote) AddText(sink, $"[{fl.Footnote?.Label}]", f);
                    else sink.Add(AddFootnote(fl.Footnote, c));
                    break;
                case ContainerInline ci:
                    AppendInlines(sink, ci, f, c);
                    break;
                default:
                    Warn($"unsupported inline '{inline.GetType().Name}' was skipped");
                    break;
            }
        }
    }

    static RunFormat ApplyEmphasis(EmphasisInline em, RunFormat f) => em.DelimiterChar switch
    {
        '*' or '_' => em.DelimiterCount >= 3 ? f with { Bold = true, Italic = true } : em.DelimiterCount == 2 ? f with { Bold = true } : f with { Italic = true },
        '~' => em.DelimiterCount >= 2 ? f with { Strike = true } : f with { Sub = true },
        '^' => f with { Super = true },
        '+' => f with { Underline = true },
        '=' => f with { Mark = true },
        _ => f,
    };

    void AppendLink(List<OpenXmlElement> sink, LinkInline link, RunFormat f, Ctx c)
    {
        var lf = ResolveLink(link.Url, link.Title, f);
        if (link.FirstChild is null)
        {
            if (!string.IsNullOrEmpty(link.Url)) AddText(sink, Clean(link.Url), lf);
            return;
        }
        AppendInlines(sink, link, lf, c);
    }

    RunFormat ResolveLink(string? url, string? title, RunFormat f)
    {
        if (string.IsNullOrWhiteSpace(url)) return f;
        url = url.Trim();
        if (url.StartsWith('#'))
        {
            var id = Uri.UnescapeDataString(url[1..]);
            if (_anchors.TryGetValue(id, out var bookmark)) return f with { Anchor = bookmark, Href = null, Tooltip = title };
            Warn($"link target '{url}' does not match any heading; left as plain text");
            return f;
        }
        if (Uri.TryCreate(url, UriKind.Absolute, out var abs))
        {
            if (!SafeSchemes.Contains(abs.Scheme))
            {
                Warn($"link scheme '{abs.Scheme}:' is not allowed; left '{Truncate(url)}' as plain text");
                return f;
            }
            return f with { Href = url, Anchor = null, Tooltip = title };
        }
        if (Uri.TryCreate(url, UriKind.Relative, out _)) return f with { Href = url, Anchor = null, Tooltip = title };
        Warn($"malformed link '{Truncate(url)}'; left as plain text");
        return f;
    }

    static string Truncate(string s) => s.Length <= 60 ? s : s[..57] + "...";

    RunProperties? RunProps(RunFormat f)
    {
        var rPr = new RunProperties();
        if (f.IsLink) rPr.RunStyle = new RunStyle { Val = "Hyperlink" };
        else if (f.Code) rPr.RunStyle = new RunStyle { Val = "CodeChar" };
        if (f.Code && f.IsLink) rPr.RunFonts = new RunFonts { Ascii = MonoFont, HighAnsi = MonoFont, ComplexScript = MonoFont, EastAsia = MonoFont };
        if (f.Bold) rPr.Bold = new Bold();
        if (f.Italic) rPr.Italic = new Italic();
        if (f.Strike) rPr.Strike = new Strike();
        if (f.Color is not null) rPr.Color = new Color { Val = f.Color };
        if (f.Mark) rPr.Highlight = new Highlight { Val = HighlightColorValues.Yellow };
        if (f.Underline && !f.IsLink) rPr.Underline = new Underline { Val = UnderlineValues.Single };
        if (f.Sub) rPr.VerticalTextAlignment = new VerticalTextAlignment { Val = VerticalPositionValues.Subscript };
        else if (f.Super) rPr.VerticalTextAlignment = new VerticalTextAlignment { Val = VerticalPositionValues.Superscript };
        return rPr.HasChildren ? rPr : null;
    }

    OpenXmlElement WrapLink(Run run, RunFormat f)
    {
        if (f.Anchor is not null)
        {
            var anchored = new Hyperlink { Anchor = f.Anchor, History = true };
            if (f.Tooltip is not null) anchored.Tooltip = Clean(f.Tooltip);
            anchored.Append(run);
            return anchored;
        }
        if (f.Href is null) return run;
        if (!_hyperlinkIds.TryGetValue(f.Href, out var relId))
        {
            relId = _main.AddHyperlinkRelationship(new Uri(f.Href, UriKind.RelativeOrAbsolute), true).Id;
            _hyperlinkIds[f.Href] = relId;
        }
        var link = new Hyperlink { Id = relId, History = true };
        if (f.Tooltip is not null) link.Tooltip = Clean(f.Tooltip);
        link.Append(run);
        return link;
    }

    void AddText(Paragraph p, string text, RunFormat f)
    {
        var tmp = new List<OpenXmlElement>();
        _lastTextRun = null;
        AddText(tmp, text, f);
        _lastTextRun = null;
        foreach (var e in tmp) p.Append(e);
    }

    void AddText(List<OpenXmlElement> sink, string text, RunFormat f)
    {
        if (text.Length == 0) return;
        var simple = text.IndexOfAny(['\t', '\n', '\r']) < 0;
        if (simple && !f.IsLink && _lastTextRun is not null && _lastTextFormat == f && sink.Count > 0 && ReferenceEquals(sink[^1], _lastTextRun)
            && _lastTextRun.LastChild is Text prev)
        {
            prev.Text += text;
            return;
        }

        var run = new Run();
        if (RunProps(f) is { } rPr) run.Append(rPr);
        var sb = new StringBuilder();
        void Flush()
        {
            if (sb.Length == 0) return;
            run.Append(new Text(sb.ToString()) { Space = SpaceProcessingModeValues.Preserve });
            sb.Clear();
        }
        foreach (var ch in text)
        {
            switch (ch)
            {
                case '\t': Flush(); run.Append(new TabChar()); break;
                case '\n': Flush(); run.Append(new Break()); break;
                case '\r': break;
                default: sb.Append(ch); break;
            }
        }
        Flush();
        sink.Add(WrapLink(run, f));
        if (simple && !f.IsLink) { _lastTextRun = run; _lastTextFormat = f; }
        else _lastTextRun = null;
    }

    // ── html ────────────────────────────────────────────────────────────────

    void HandleInlineHtml(List<OpenXmlElement> sink, HtmlState state, string raw, RunFormat f, Ctx c)
    {
        if (raw.StartsWith("<!--", StringComparison.Ordinal)) return;
        var tag = HtmlTag.Parse(raw);
        if (tag is null) return;
        switch (tag.Name)
        {
            case "br":
                sink.Add(new Run(new Break()));
                _lastTextRun = null;
                break;
            case "img":
                AddImage(sink, tag.Attrs.GetValueOrDefault("src"), tag.Attrs.GetValueOrDefault("alt") ?? string.Empty, f, c);
                break;
            default:
                ApplyFormatTag(state, tag, f);
                break;
        }
    }

    void ApplyFormatTag(HtmlState s, HtmlTag t, RunFormat f)
    {
        var on = !t.Closing;
        switch (t.Name)
        {
            case "b" or "strong": s.Bold = on; break;
            case "i" or "em" or "cite" or "dfn" or "var": s.Italic = on; break;
            case "u" or "ins": s.Underline = on; break;
            case "s" or "strike" or "del": s.Strike = on; break;
            case "sub": s.Sub = on; break;
            case "sup": s.Super = on; break;
            case "code" or "kbd" or "samp" or "tt": s.Code = on; break;
            case "mark": s.Mark = on; break;
            case "a":
                if (!on || !t.Attrs.TryGetValue("href", out var href)) { s.Href = null; s.Anchor = null; break; }
                var resolved = ResolveLink(href, t.Attrs.GetValueOrDefault("title"), f);
                s.Href = resolved.Href;
                s.Anchor = resolved.Anchor;
                break;
        }
    }

    void RenderHtml(string html, Ctx c, List<OpenXmlElement> sink)
    {
        var state = new HtmlState();
        var current = new List<OpenXmlElement>();
        string? headingStyle = null;
        var preBuffer = (StringBuilder?)null;

        void FlushParagraph()
        {
            if (current.Count == 0) return;
            var hasContent = current.Any(e => e.Descendants<Text>().Any(t => !string.IsNullOrWhiteSpace(t.Text)) || e.Descendants<Drawing>().Any() || e.Descendants<Break>().Any());
            if (hasContent)
            {
                var p = NewParagraph(c, headingStyle);
                foreach (var e in current) p.Append(e);
                sink.Add(p);
            }
            current = [];
            _lastTextRun = null;
        }

        foreach (Match token in HtmlTokenRx.Matches(html))
        {
            var raw = token.Value;
            if (raw.StartsWith("<!--", StringComparison.Ordinal)) continue;

            if (raw.Length > 1 && raw[0] == '<' && (char.IsLetter(raw[1]) || raw[1] == '/'))
            {
                var tag = HtmlTag.Parse(raw);
                if (tag is null) continue;

                if (tag.Name == "pre")
                {
                    if (!tag.Closing) { FlushParagraph(); preBuffer = new StringBuilder(); }
                    else if (preBuffer is not null)
                    {
                        RenderCode(WebUtility.HtmlDecode(preBuffer.ToString()).Replace("\r\n", "\n").Split('\n'), c, sink);
                        preBuffer = null;
                    }
                    continue;
                }
                if (preBuffer is not null) continue;

                if (tag.Name is "h1" or "h2" or "h3" or "h4" or "h5" or "h6")
                {
                    FlushParagraph();
                    headingStyle = tag.Closing ? null : $"Heading{tag.Name[1]}";
                    continue;
                }
                switch (tag.Name)
                {
                    case "br":
                        current.Add(new Run(new Break()));
                        _lastTextRun = null;
                        continue;
                    case "hr":
                        FlushParagraph();
                        sink.Add(ThematicBreak(c));
                        continue;
                    case "img":
                        AddImage(current, tag.Attrs.GetValueOrDefault("src"), tag.Attrs.GetValueOrDefault("alt") ?? string.Empty, state.Overlay(c.BaseFormat), c);
                        continue;
                    case "li" when !tag.Closing:
                        FlushParagraph();
                        AddText(current, "\u2022 ", c.BaseFormat);
                        continue;
                    case "td" or "th" when tag.Closing:
                        AddText(current, "\t", c.BaseFormat);
                        continue;
                    case "summary":
                        FlushParagraph();
                        state.Bold = !tag.Closing;
                        continue;
                }
                if (BlockTags.Contains(tag.Name)) FlushParagraph();
                else ApplyFormatTag(state, tag, c.BaseFormat);
                continue;
            }

            if (preBuffer is not null)
            {
                preBuffer.Append(Regex.Replace(raw, "<[^>]+>", string.Empty));
                continue;
            }

            var text = Regex.Replace(WebUtility.HtmlDecode(raw), @"\s+", " ");
            if (current.Count == 0 || current[^1] is Run { LastChild: Break }) text = text.TrimStart();
            if (text.Length > 0) AddText(current, Clean(text), state.Overlay(c.BaseFormat));
        }
        FlushParagraph();
    }

    // ── images ──────────────────────────────────────────────────────────────

    void AddImage(List<OpenXmlElement> sink, string? url, string alt, RunFormat f, Ctx c)
    {
        var label = string.IsNullOrWhiteSpace(alt) ? "image" : alt;
        var run = TryBuildImageRun(url, alt, c, out var problem);
        if (run is not null)
        {
            _lastTextRun = null;
            sink.Add(WrapLink(run, f));
            return;
        }
        Warn(problem!);
        AddText(sink, $"[image: {Clean(label)}]", f with { Italic = true, Color = f.Color ?? "656D76" });
    }

    Run? TryBuildImageRun(string? url, string alt, Ctx c, out string? problem)
    {
        problem = null;
        if (string.IsNullOrWhiteSpace(url)) { problem = "image with an empty source was replaced by a text placeholder"; return null; }
        url = url.Trim();

        byte[] data;
        string key;
        if (url.StartsWith("data:", StringComparison.OrdinalIgnoreCase))
        {
            var m = Regex.Match(url, @"^data:[^;,]*;base64,(.*)$", RegexOptions.Singleline | RegexOptions.IgnoreCase);
            if (!m.Success) { problem = "data: image is not base64-encoded; replaced by a text placeholder"; return null; }
            try { data = System.Convert.FromBase64String(m.Groups[1].Value); }
            catch (FormatException) { problem = "data: image has invalid base64; replaced by a text placeholder"; return null; }
            key = "data:" + System.Convert.ToHexString(System.Security.Cryptography.SHA1.HashData(data));
        }
        else if (Regex.IsMatch(url, @"^[A-Za-z][A-Za-z0-9+.-]*://") && !url.StartsWith("file://", StringComparison.OrdinalIgnoreCase))
        {
            problem = $"remote image '{Truncate(url)}' is not downloaded; download it and reference the local file";
            return null;
        }
        else
        {
            var rel = url.StartsWith("file://", StringComparison.OrdinalIgnoreCase) ? new Uri(url).LocalPath : Uri.UnescapeDataString(url);
            var cut = rel.IndexOfAny(['?', '#']);
            if (cut > 0 && !File.Exists(Path.GetFullPath(Path.Combine(_baseDir, rel)))) rel = rel[..cut];
            var full = Path.GetFullPath(Path.Combine(_baseDir, rel));
            var rootWithSep = Path.TrimEndingDirectorySeparator(_imageRoot) + Path.DirectorySeparatorChar;
            if (!full.StartsWith(rootWithSep, StringComparison.Ordinal))
            {
                problem = $"image '{Truncate(url)}' is outside the image root {_imageRoot}; pass --image-root to allow it";
                return null;
            }
            if (!File.Exists(full)) { problem = $"image not found: {Truncate(url)}"; return null; }
            try { data = File.ReadAllBytes(full); }
            catch (Exception ex) { problem = $"cannot read image '{Truncate(url)}': {ex.Message}"; return null; }
            key = full;
        }

        if (!_imageParts.TryGetValue(key, out var part))
        {
            var info = ImageProbe.Probe(data);
            if (info is not { } known || known.Width <= 0 || known.Height <= 0)
            {
                problem = $"image '{Truncate(url)}' is not a PNG, JPEG, GIF or BMP (SVG/WebP are not supported); replaced by a text placeholder";
                return null;
            }
            var imagePart = known.ContentType switch
            {
                "png" => _main.AddImagePart(ImagePartType.Png),
                "jpeg" => _main.AddImagePart(ImagePartType.Jpeg),
                "gif" => _main.AddImagePart(ImagePartType.Gif),
                _ => _main.AddImagePart(ImagePartType.Bmp),
            };
            using (var ms = new MemoryStream(data)) imagePart.FeedData(ms);
            part = (_main.GetIdOfPart(imagePart), known);
            _imageParts[key] = part;
        }

        const double EmuPerPx = 9525;
        double cx = part.Info.Width * EmuPerPx, cy = part.Info.Height * EmuPerPx;
        var maxW = (double)(c.ImageBudgetEmu ?? Math.Max(_contentW - c.Left, 1440) * (long)TwipEmu);
        var maxH = 8.0 * 914400;
        var scale = Math.Min(1.0, Math.Min(maxW / cx, maxH / cy));
        var w = Math.Max((long)(cx * scale), 1);
        var h = Math.Max((long)(cy * scale), 1);
        return new Run(BuildDrawing(part.RelId, _drawingId++, Clean(alt), w, h));
    }

    static Drawing BuildDrawing(string relId, uint id, string alt, long cx, long cy) =>
        new(new Wp.Inline(
            new Wp.Extent { Cx = cx, Cy = cy },
            new Wp.EffectExtent { LeftEdge = 0, TopEdge = 0, RightEdge = 0, BottomEdge = 0 },
            new Wp.DocProperties { Id = id, Name = $"Image {id}", Description = alt },
            new Wp.NonVisualGraphicFrameDrawingProperties(new A.GraphicFrameLocks { NoChangeAspect = true }),
            new A.Graphic(new A.GraphicData(
                new Pic.Picture(
                    new Pic.NonVisualPictureProperties(
                        new Pic.NonVisualDrawingProperties { Id = 0, Name = $"Image {id}" },
                        new Pic.NonVisualPictureDrawingProperties()),
                    new Pic.BlipFill(new A.Blip { Embed = relId }, new A.Stretch(new A.FillRectangle())),
                    new Pic.ShapeProperties(
                        new A.Transform2D(new A.Offset { X = 0, Y = 0 }, new A.Extents { Cx = cx, Cy = cy }),
                        new A.PresetGeometry(new A.AdjustValueList()) { Preset = A.ShapeTypeValues.Rectangle })))
            { Uri = "http://schemas.openxmlformats.org/drawingml/2006/picture" }))
        { DistanceFromTop = 0U, DistanceFromBottom = 0U, DistanceFromLeft = 0U, DistanceFromRight = 0U });

    // ── footnotes ───────────────────────────────────────────────────────────

    OpenXmlElement AddFootnote(MdFootnote? source, Ctx c)
    {
        if (_footnotesPart is null)
        {
            _footnotesPart = _main.AddNewPart<FootnotesPart>();
            _footnotesPart.Footnotes = new Footnotes(
                new WFootnote(new Paragraph(new ParagraphProperties(new SpacingBetweenLines { After = "0", Line = "240", LineRule = LineSpacingRuleValues.Auto }), new Run(new SeparatorMark())))
                { Type = FootnoteEndnoteValues.Separator, Id = -1 },
                new WFootnote(new Paragraph(new ParagraphProperties(new SpacingBetweenLines { After = "0", Line = "240", LineRule = LineSpacingRuleValues.Auto }), new Run(new ContinuationSeparatorMark())))
                { Type = FootnoteEndnoteValues.ContinuationSeparator, Id = 0 });
        }

        var id = _nextFootnoteId++;
        var note = new WFootnote { Id = id };
        var fc = new Ctx { InFootnote = true, BaseStyle = "FootnoteText", ImageBudgetEmu = (long)(_contentW - 720) * TwipEmu };
        var blocks = new List<OpenXmlElement>();
        if (source is not null) RenderBlocks(source, fc, blocks);
        if (blocks.OfType<Paragraph>().FirstOrDefault() is not { } first)
        {
            first = new Paragraph(new ParagraphProperties(new ParagraphStyleId { Val = "FootnoteText" }));
            blocks.Insert(0, first);
        }
        var mark = new Run(new RunProperties(new RunStyle { Val = "FootnoteReference" }), new FootnoteReferenceMark());
        var space = new Run(new Text(" ") { Space = SpaceProcessingModeValues.Preserve });
        if (first.ParagraphProperties is { } pPr) { pPr.InsertAfterSelf(mark); mark.InsertAfterSelf(space); }
        else { first.PrependChild(space); first.PrependChild(mark); }
        foreach (var b in blocks) note.Append(b);
        _footnotesPart.Footnotes!.Append(note);

        return new Run(new RunProperties(new RunStyle { Val = "FootnoteReference" }), new FootnoteReference { Id = id });
    }
}
