using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Validation;
using System.Text.Json;

if (args.Length < 1 || args.Length > 2) throw new ArgumentException("Pass the generated package fixture directory and optional filename stem");
var results = new List<object>();
foreach (var extension in new[] { "docx", "pptx" })
{
    var file = Path.Combine(args[0], (args.Length == 2 ? args[1] : "editable") + "." + extension);
    using OpenXmlPackage package = extension == "docx"
        ? WordprocessingDocument.Open(file, false)
        : PresentationDocument.Open(file, false);
    var errors = new OpenXmlValidator(FileFormatVersions.Office2016).Validate(package)
        .Select(error => new { error.Description, Path = error.Path?.XPath, Part = error.Part?.Uri.ToString() }).ToArray();
    results.Add(new { extension, errors });
    if (errors.Length != 0) Environment.ExitCode = 1;
}
Console.WriteLine(JsonSerializer.Serialize(results, new JsonSerializerOptions { WriteIndented = true }));
