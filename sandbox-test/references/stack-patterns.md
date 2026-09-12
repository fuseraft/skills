# Stack Patterns

sandbox-test targets .NET (C#) projects only. This reference covers detection markers, the
scaffold/build/run/cleanup commands, the debug output idiom, and notes for that stack.

Use `<harness_dir>` as a placeholder for the full harness path. Form it as:
- **bash / zsh:** `$TMPDIR/harness-<name>-<ts>`
- **PowerShell:** `"$env:TEMP\harness-<name>-<ts>"`

The `detect_stack` script resolves the correct temp directory and shell automatically — read its output instead of constructing paths manually.

**stderr capture:** `2>&1` works on bash, zsh, and PowerShell. Append it to any run command to merge stderr with stdout.

---

## .NET (C#)

**Markers:** `*.csproj`, `*.sln`, `global.json`, `Directory.Build.props`

**Scaffold:**
```
# bash
dotnet new console -o <harness_dir> --force

# PowerShell
dotnet new console -o '<harness_dir>' --force
```

`dotnet` accepts both forward and back slashes on all platforms; only the quoting convention differs.

**Build:** `dotnet build`
**Run:** `dotnet run`
**Cleanup:**
```
rm -rf <harness_dir>          # bash
Remove-Item -Recurse -Force '<harness_dir>'   # PowerShell
```

**Debug idiom:**
```csharp
Console.WriteLine($"[DBG] label={value}");
Console.WriteLine($"[DBG] obj={System.Text.Json.JsonSerializer.Serialize(obj)}");
```

**Notes:**
- The generated `.csproj` includes `<ImplicitUsings>enable</ImplicitUsings>` and `<Nullable>enable</Nullable>` by default in .NET 6+; no manual edits needed for basic harnesses.
- Use `dotnet add package <Package>` if a lightweight dependency is unavoidable. Prefer inlining relevant logic instead.
- Exceptions go to stderr; `2>&1` ensures they appear in captured output.
- If the project also has a test project (`*.Tests.csproj`), a scratch xUnit/NUnit test can be faster to iterate on than a console harness when the logic under test already has test doubles set up — use judgment on which scaffold fits the situation.
