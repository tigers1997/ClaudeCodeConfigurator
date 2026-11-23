#:package Microsoft.AnalysisServices@19.120.1

// tmdl-check: parse each TMDL definition folder with the Tabular Object Model's
// own TMDL serializer, the same parser Power BI Desktop and Fabric use.
//
//   dotnet run scripts/tmdl-check.cs -- <definition folder>...
//
// Prints one `OK` or `FAIL` line per folder (a FAIL carries the parser's message,
// which names the file and line) and exits 1 if any folder failed.
//
// What this proves: the files are well-formed TMDL, every object that is
// referenced exists, and no two objects clash. What it does NOT prove, verified
// against this parser: DAX and M expressions are read verbatim, so unbalanced
// parentheses, an undefined function, a reference to a table that does not exist
// and circular measure dependencies all PASS. The offline check on those is a
// reviewer; a live engine (Power BI Modeling MCP, XMLA) is the only machine check.
//
// Needs the .NET 10 SDK (file-based apps). The package version above is the pin;
// bump it deliberately.

using Microsoft.AnalysisServices.Tabular;

if (args.Length == 0)
{
    Console.Error.WriteLine("usage: dotnet run scripts/tmdl-check.cs -- <TMDL definition folder>...");
    return 2;
}

var failed = 0;
foreach (var folder in args)
{
    try
    {
        var db = TmdlSerializer.DeserializeDatabaseFromFolder(folder);
        var measures = db.Model.Tables.Sum(t => t.Measures.Count);
        Console.WriteLine($"OK    {folder}: {db.Model.Tables.Count} tables, {measures} measures, {db.Model.Relationships.Count} relationships");
    }
    catch (Exception e)
    {
        Console.WriteLine($"FAIL  {folder}: {e.GetType().Name}: {e.Message}");
        failed++;
    }
}
return failed == 0 ? 0 : 1;
