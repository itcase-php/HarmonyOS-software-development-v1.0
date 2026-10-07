// Independent port probe for controlled local fixtures, not an application engine.
#include <LibreOfficeKit/LibreOfficeKitInit.h>

#include <cstdio>
#include <cstring>

static void reportError(LibreOfficeKit* office, const char* stage)
{
    char* error = office->pClass->getError(office);
    std::fprintf(stderr, "%s failed: %s\n", stage, error ? error : "no engine detail");
    if (error)
        office->pClass->freeError(error);
}

int main(int argc, char** argv)
{
    if (argc != 5 || argv[1][0] != '/' ||
        std::strncmp(argv[2], "file:///", 8) != 0 ||
        std::strncmp(argv[3], "file:///", 8) != 0 ||
        std::strncmp(argv[4], "file:///", 8) != 0 ||
        std::strcmp(argv[3], argv[4]) == 0)
    {
        std::fprintf(stderr, "Usage: hdm_office_lok_probe /absolute/program "
            "file:///profile file:///input.docx-or-pptx file:///new-output.pdf\n");
        return 64;
    }

    LibreOfficeKit* office = lok_init_2(argv[1], argv[2]);
    if (!office)
    {
        std::fprintf(stderr, "LibreOfficeKit initialization failed\n");
        return 2;
    }

    LibreOfficeKitDocument* document = office->pClass->documentLoadWithOptions(
        office, argv[3], "EnableMacrosExecution=false");
    if (!document)
    {
        reportError(office, "document load");
        office->pClass->destroy(office);
        return 3;
    }

    const int type = document->pClass->getDocumentType(document);
    int status = 0;
    if (!document->pClass->saveAs(document, argv[4], "pdf", nullptr))
    {
        reportError(office, "PDF export");
        status = 5;
    }
    document->pClass->destroy(document);
    office->pClass->destroy(office);
    if (status == 0)
        std::printf("Engine reported PDF export success (type=%d): %s\n"
            "Independent PDF content/layout validation is still required.\n", type, argv[4]);
    return status;
}
