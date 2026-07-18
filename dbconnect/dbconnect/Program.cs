using System.CommandLine;
using System.Data.Common;
using System.Globalization;
using System.Text;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using Oracle.ManagedDataAccess.Client;

var connectionOption = new Option<string?>(
    name: "--conn",
    description: "The connection string to use.");

var useOption = new Option<string?>(
    name: "--use",
    description: "Specify a named connection to use.");

var listOption = new Option<bool>(
    name: "--list",
    description: "List available connections.");

var sqlOption = new Option<string?>(
    name: "--sql",
    description: "SQL text to execute, or a path to a file containing SQL.");

var outputOption = new Option<string?>(
    name: "--output",
    description: "Write tabular results to a CSV file.");

var oracleOption = new Option<bool>(
    name: "--oracle",
    description: "Connect to an Oracle database using Kerberos.");

var rootCommand = new RootCommand("Connect to a database and execute SQL.");
rootCommand.AddOption(connectionOption);
rootCommand.AddOption(useOption);
rootCommand.AddOption(listOption);
rootCommand.AddOption(sqlOption);
rootCommand.AddOption(outputOption);
rootCommand.AddOption(oracleOption);

rootCommand.SetHandler(async context =>
{
    var parseResult = context.ParseResult;
    var connectionString = parseResult.GetValueForOption(connectionOption);
    var useName = parseResult.GetValueForOption(useOption);
    var listConnections = parseResult.GetValueForOption(listOption);
    var sqlInput = parseResult.GetValueForOption(sqlOption);
    var outputPath = parseResult.GetValueForOption(outputOption);
    var useOracle = parseResult.GetValueForOption(oracleOption);

    try
    {
        var availableConnections = await LoadConnectionDefinitionsAsync();

        if (listConnections)
        {
            if (!string.IsNullOrWhiteSpace(connectionString)
                || !string.IsNullOrWhiteSpace(useName)
                || !string.IsNullOrWhiteSpace(sqlInput)
                || !string.IsNullOrWhiteSpace(outputPath)
                || useOracle)
            {
                throw new ArgumentException("--list cannot be combined with --conn, --use, --sql, --output, or --oracle.");
            }

            ListConnections(availableConnections);
            context.ExitCode = 0;
            return;
        }

        if (!string.IsNullOrWhiteSpace(connectionString) && !string.IsNullOrWhiteSpace(useName))
        {
            throw new ArgumentException("Specify either --conn or --use, but not both.");
        }

        var selectedConnection = ResolveConnection(connectionString, useName, availableConnections, useOracle);

        if (string.IsNullOrWhiteSpace(sqlInput))
        {
            throw new ArgumentException("A non-empty SQL input is required.", nameof(sqlInput));
        }

        var sqlText = await ResolveSqlTextAsync(sqlInput);
        var executionExitCode = await ExecuteAsync(selectedConnection.ConnectionString, sqlText, outputPath, selectedConnection.UseOracle);
        context.ExitCode = executionExitCode;
    }
    catch (ArgumentException ex)
    {
        Console.Error.WriteLine($"Argument error: {ex.Message}");
        context.ExitCode = 2;
    }
    catch (FileNotFoundException ex)
    {
        Console.Error.WriteLine($"File error: {ex.Message}");
        context.ExitCode = 3;
    }
    catch (DbException ex)
    {
        Console.Error.WriteLine($"Database error: {ex.Message}");
        context.ExitCode = 4;
    }
    catch (IOException ex)
    {
        Console.Error.WriteLine($"I/O error: {ex.Message}");
        context.ExitCode = 5;
    }
    catch (JsonException ex)
    {
        Console.Error.WriteLine($"Configuration error: {ex.Message}");
        context.ExitCode = 6;
    }
    catch (Exception ex)
    {
        Console.Error.WriteLine($"Unexpected error: {ex.Message}");
        context.ExitCode = 1;
    }
});

return await rootCommand.InvokeAsync(args);

static async Task<string> ResolveSqlTextAsync(string sqlInput)
{
    if (string.IsNullOrWhiteSpace(sqlInput))
    {
        throw new ArgumentException("SQL input cannot be empty.", nameof(sqlInput));
    }

    if (LooksLikeExistingOrIntendedFilePath(sqlInput))
    {
        if (!File.Exists(sqlInput))
        {
            throw new FileNotFoundException("The SQL file could not be found.", sqlInput);
        }

        var sqlFromFile = await File.ReadAllTextAsync(sqlInput);
        if (string.IsNullOrWhiteSpace(sqlFromFile))
        {
            throw new ArgumentException("The SQL file is empty.", nameof(sqlInput));
        }

        return sqlFromFile;
    }

    return sqlInput;
}

static bool LooksLikeExistingOrIntendedFilePath(string sqlInput)
{
    if (File.Exists(sqlInput))
    {
        return true;
    }

    if (sqlInput.IndexOfAny(['\r', '\n']) >= 0)
    {
        return false;
    }

    var trimmed = sqlInput.Trim();
    if (trimmed.Contains(' ') && !trimmed.Contains(Path.DirectorySeparatorChar) && !trimmed.Contains(Path.AltDirectorySeparatorChar))
    {
        return false;
    }

    return trimmed.EndsWith(".sql", StringComparison.OrdinalIgnoreCase)
        || trimmed.EndsWith(".txt", StringComparison.OrdinalIgnoreCase)
        || trimmed.Contains(Path.DirectorySeparatorChar)
        || trimmed.Contains(Path.AltDirectorySeparatorChar);
}

static async Task<IReadOnlyList<NamedConnection>> LoadConnectionDefinitionsAsync()
{
    var exeDirectory = AppContext.BaseDirectory;
    var searchDirectory = Directory.Exists(exeDirectory) ? exeDirectory : Directory.GetCurrentDirectory();
    
    var connectionFiles = Directory
        .EnumerateFiles(searchDirectory, "*.connections", SearchOption.TopDirectoryOnly)
        .OrderBy(path => path, StringComparer.OrdinalIgnoreCase)
        .ToList();

    var results = new List<NamedConnection>();

    foreach (var file in connectionFiles)
    {
        await using var stream = File.OpenRead(file);
        var document = await JsonSerializer.DeserializeAsync<ConnectionsDocument>(stream, JsonOptions())
            ?? throw new JsonException($"Connection file '{Path.GetFileName(file)}' is empty or invalid.");

        if (document.Connections is null)
        {
            continue;
        }

        foreach (var connection in document.Connections)
        {
            if (connection is null)
            {
                continue;
            }

            if (string.IsNullOrWhiteSpace(connection.Name))
            {
                throw new JsonException($"Connection file '{Path.GetFileName(file)}' contains a connection with no name.");
            }

            if (string.IsNullOrWhiteSpace(connection.ConnectionString))
            {
                throw new JsonException($"Connection '{connection.Name}' in '{Path.GetFileName(file)}' has no connectionstring.");
            }

            results.Add(new NamedConnection(
                connection.Name,
                connection.ConnectionString,
                DetermineUseOracle(connection.Type),
                Path.GetFileName(file),
                connection.Type));
        }
    }

    return results;
}

static ResolvedConnection ResolveConnection(string? connectionString, string? useName, IReadOnlyList<NamedConnection> availableConnections, bool useOracle)
{
    if (!string.IsNullOrWhiteSpace(connectionString))
    {
        return new ResolvedConnection(connectionString, useOracle);
    }

    if (!string.IsNullOrWhiteSpace(useName))
    {
        var match = availableConnections.FirstOrDefault(connection => string.Equals(connection.Name, useName, StringComparison.OrdinalIgnoreCase));
        if (match is null)
        {
            throw new ArgumentException($"Named connection '{useName}' was not found.", nameof(useName));
        }

        return new ResolvedConnection(match.ConnectionString, match.UseOracle);
    }

    throw new ArgumentException("Specify either --conn or --use.");
}

static void ListConnections(IReadOnlyList<NamedConnection> availableConnections)
{
    if (availableConnections.Count == 0)
    {
        var exeDirectory = AppContext.BaseDirectory;
        var searchDirectory = Directory.Exists(exeDirectory) ? exeDirectory : Directory.GetCurrentDirectory();
        Console.WriteLine($"No .connections files were found in '{searchDirectory}'.");
        return;
    }

    foreach (var connection in availableConnections.OrderBy(connection => connection.Name, StringComparer.OrdinalIgnoreCase))
    {
        var typeLabel = string.IsNullOrWhiteSpace(connection.Type) ? "unknown" : connection.Type;
        Console.WriteLine($"{connection.Name}\t{typeLabel}\t{connection.SourceFile}");
    }
}

static bool DetermineUseOracle(string? type)
{
    if (string.IsNullOrWhiteSpace(type))
    {
        return false;
    }

    return string.Equals(type, "oracle", StringComparison.OrdinalIgnoreCase);
}

static JsonSerializerOptions JsonOptions() => new()
{
    PropertyNameCaseInsensitive = true
};

static async Task<int> ExecuteAsync(string connectionString, string sqlText, string? outputPath, bool useOracle)
{
    if (string.IsNullOrWhiteSpace(sqlText))
    {
        throw new ArgumentException("SQL text cannot be empty.", nameof(sqlText));
    }

    if (string.IsNullOrWhiteSpace(outputPath) == false && ContainsInvalidPathChars(outputPath))
    {
        throw new ArgumentException("The output path contains invalid characters.", nameof(outputPath));
    }

    using var connection = useOracle
        ? CreateOracleConnection(connectionString)
        : CreateSqlServerConnection(connectionString);

    await connection.OpenAsync();

    using var command = connection.CreateCommand();
    command.CommandText = sqlText;

    using var reader = await command.ExecuteReaderAsync();

    if (reader.FieldCount > 0)
    {
        var rows = await ReadRowsAsync(reader);

        if (!string.IsNullOrWhiteSpace(outputPath))
        {
            await WriteCsvAsync(outputPath, rows);
            Console.WriteLine($"Wrote {Math.Max(rows.Count - 1, 0)} row(s) to {outputPath}.");
            return 0;
        }

        WriteConsoleTable(rows);
        return 0;
    }

    var affectedRows = reader.RecordsAffected;
    Console.WriteLine(affectedRows >= 0
        ? $"Command completed successfully. {affectedRows} row(s) affected."
        : "Command completed successfully.");

    return 0;
}

static bool ContainsInvalidPathChars(string path) => path.IndexOfAny(Path.GetInvalidPathChars()) >= 0;

static DbConnection CreateSqlServerConnection(string connectionString) => new SqlConnection(connectionString);

static DbConnection CreateOracleConnection(string connectionString)
{
    OracleConfiguration.SqlNetAuthenticationServices = "(KERBEROS5)";
    return new OracleConnection(connectionString);
}

static async Task<List<string[]>> ReadRowsAsync(DbDataReader reader)
{
    var rows = new List<string[]>();
    var header = new string[reader.FieldCount];
    for (var i = 0; i < reader.FieldCount; i++)
    {
        header[i] = reader.GetName(i);
    }

    rows.Add(header);

    while (await reader.ReadAsync())
    {
        var values = new string[reader.FieldCount];
        for (var i = 0; i < reader.FieldCount; i++)
        {
            values[i] = reader.IsDBNull(i)
                ? string.Empty
                : Convert.ToString(reader.GetValue(i), CultureInfo.InvariantCulture) ?? string.Empty;
        }

        rows.Add(values);
    }

    return rows;
}

static async Task WriteCsvAsync(string outputPath, IReadOnlyList<string[]> rows)
{
    var directory = Path.GetDirectoryName(Path.GetFullPath(outputPath));
    if (!string.IsNullOrWhiteSpace(directory))
    {
        Directory.CreateDirectory(directory);
    }

    await using var writer = new StreamWriter(outputPath, false, new UTF8Encoding(false));
    foreach (var row in rows)
    {
        await writer.WriteLineAsync(string.Join(',', row.Select(EscapeCsv)));
    }
}

static string EscapeCsv(string value)
{
    if (value.Contains(',') || value.Contains('"') || value.Contains('\n') || value.Contains('\r'))
    {
        return $"\"{value.Replace("\"", "\"\"")}\"";
    }

    return value;
}

static void WriteConsoleTable(IReadOnlyList<string[]> rows)
{
    foreach (var row in rows)
    {
        Console.WriteLine(string.Join('\t', row));
    }
}

sealed record ResolvedConnection(string ConnectionString, bool UseOracle);

sealed record NamedConnection(string Name, string ConnectionString, bool UseOracle, string SourceFile, string? Type);

sealed class ConnectionsDocument
{
    public List<ConnectionDefinition>? Connections { get; init; }
}

sealed class ConnectionDefinition
{
    public string? Name { get; init; }

    public string? ConnectionString { get; init; }

    public string? Type { get; init; }
}
