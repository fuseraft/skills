---
name: build-docx
description: "Convert Markdown to a Word (.docx) document with a deterministic, schema-validated converter: GitHub-flavored Markdown including headings, nested and task lists, tables, code blocks, footnotes, images, alerts, and links. Trigger when the user wants a Word document or .docx, wants agent output (reports, specs, briefs, changelogs) exported to Word, or has a Markdown file to convert. If the content is only a description or outline, write it as Markdown first, then convert. Requires the .NET 10 SDK. Does not support templates, headers/footers, page numbers, or a table of contents."
compatibility: "Requires the .NET 10 SDK (`dotnet`). The first run needs network access to restore two NuGet packages (Markdig, DocumentFormat.OpenXml)."
---

# Build DOCX

`scripts/md2docx.cs` converts Markdown to `.docx` (Markdig parser, OpenXML SDK writer). Use it as-is. Do not hand-write a Markdown parser or a `python-docx`/`docx` script: the converter already handles nesting, numbering, escaping, and Word's structural rules.

## Steps

1. **Get the content into a Markdown file.** If the user gave a description or outline, write the Markdown yourself first. Prefer local images referenced by relative path.
2. **Run the converter** using absolute paths. The shell tool works on every fuseraft version:

   ```bash
   dotnet run <skill-dir>/scripts/md2docx.cs -- <input.md> [output.docx] [--page letter|a4] [--image-root DIR] [--strict]
   ```

   `<skill-dir>` is this skill's directory (`~/.fuseraft/skills/build-docx` when installed globally). Recent fuseraft versions can instead run it with `run_skill_script`: script name `scripts/md2docx.cs` (the `scripts/` prefix is required) and the arguments as a string array. Older versions fail there because they cannot execute `.cs` files.

   The output defaults to the input path with `.docx`. The first run restores packages (about 15 s); later runs take about 1 s.
3. **Read the result.** Stdout is `Wrote <path> (N paragraphs, N tables, N images, N footnotes)`. Every `warning:` line on stderr is a real degradation: fix the cause and re-run, or tell the user. Do not ignore them (see the table below).
4. **Report** the absolute output path and any warnings you could not fix.

| Exit | Meaning |
|---|---|
| 0 | Written (warnings possible). |
| 1 | Bad usage or unreadable input. Read the `error:` line. |
| 2 | Conversion or schema-validation failure. No output file is written. |
| 3 | `--strict` and at least one warning. The file is still written. |

Use `--strict` when the document must be free of degradations.

## Supported Markdown

| Element | Result in Word |
|---|---|
| Headings 1-6 (ATX and setext) | Real *Heading 1-6* styles (navigation pane, TOC-ready). `[x](#heading)` links jump to the heading. |
| Bold, italic, `~~strike~~`, `==mark==`, `++ins++`, `~sub~`, `^sup^` | Run formatting, nestable. |
| Inline code, fenced and indented code | Monospace, shaded; whitespace and tabs preserved. No syntax highlighting. |
| Bullet, ordered, lettered/roman (`a.`, `i.`), `)` lists, start numbers | Real Word numbering, nested to any depth (indent is capped so text never collapses). |
| Task lists `- [ ]` / `- [x]` | Checkbox glyphs. `[ ]` elsewhere in a line stays literal. |
| Block quotes, nested; GitHub alerts (`> [!NOTE]`, `TIP`, `IMPORTANT`, `WARNING`, `CAUTION`) | Left-bar quotes; alerts get a colored title. |
| Pipe and grid tables | Alignment, repeating header row, colspan/rowspan, inline formatting and images in cells, widths sized to content. |
| Footnotes `[^1]` | Real Word footnotes. |
| Images (PNG, JPEG, GIF, BMP; local files or `data:` URIs) | Embedded and scaled to the page. Linked images stay links. |
| Links `http`, `https`, `mailto`, `tel`, `ftp`, relative | Hyperlinks; the title becomes the tooltip. |
| Definition lists | Only Markdig syntax: `Term` then `:` followed by three spaces or a tab. |
| YAML front matter | `title:` becomes the document title; the block is not rendered. |
| Raw HTML | `b i u s sub sup code kbd mark a img br hr pre h1-h6 p div li details/summary` are honored, comments are dropped, and other tags are stripped but their text is kept. |

## What degrades

Nothing is silently dropped: each of these produces a `warning:` line, and images become an italic `[image: alt]` placeholder.

| Cause | Fix |
|---|---|
| Remote image (`http(s)://`) | Never downloaded. Download it and reference the local file. |
| SVG, WebP, or other unsupported image | Convert to PNG or JPEG first. |
| Missing image, or one outside the image root | Fix the path, or pass `--image-root` (default: the input file's directory). |
| `#anchor` that matches no heading | Rendered as plain text. Fix the link (GitHub slugs keep `--` from `--json` and `read / write`). |
| `javascript:` or another unsafe link scheme | Rendered as plain text. |

Also not rendered: math (`$x^2$` stays literal), Mermaid and other diagram fences (they appear as code), and HTML attributes such as `align`. Custom templates, headers/footers, page numbers, and tables of contents are not supported. Say so rather than improvising a workaround.

## Guarantees

- The output is validated against the OpenXML schema before it is written, and written atomically, so a failure never leaves a truncated or corrupt `.docx`.
- Characters XML forbids (stray control characters) are replaced, not fatal. CRLF, UTF-8 BOM, empty files, and very large documents are handled.
- Local images are only embedded from under the image root, so a Markdown file cannot pull arbitrary files from elsewhere on disk into a document.
