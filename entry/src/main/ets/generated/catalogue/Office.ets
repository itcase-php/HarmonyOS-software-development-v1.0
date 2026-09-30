// Generated catalogue factory; records are instantiated only when queried.
import { RegistryFormat, ConversionRouteDefinition } from '../../models/RegistryTypes';
export function createFormats(): RegistryFormat[] { return [
  {
    "id": "docx",
    "displayName": "Word（DOCX）",
    "category": "office",
    "extensions": [
      "docx"
    ],
    "mimeTypes": [
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    ],
    "operations": [
      "import",
      "export"
    ],
    "defaultOptions": [
      {
        "key": "qualityMode",
        "kind": "string",
        "stringValue": "balanced"
      },
      {
        "key": "missingFontPolicy",
        "kind": "string",
        "stringValue": "reject"
      }
    ],
    "availability": "planned"
  },
  {
    "id": "pptx",
    "displayName": "PowerPoint（PPTX）",
    "category": "office",
    "extensions": [
      "pptx"
    ],
    "mimeTypes": [
      "application/vnd.openxmlformats-officedocument.presentationml.presentation"
    ],
    "operations": [
      "import",
      "export"
    ],
    "defaultOptions": [
      {
        "key": "qualityMode",
        "kind": "string",
        "stringValue": "balanced"
      },
      {
        "key": "missingFontPolicy",
        "kind": "string",
        "stringValue": "reject"
      }
    ],
    "availability": "planned"
  },
  {
    "id": "xlsx",
    "displayName": "Excel（XLSX）",
    "category": "office",
    "extensions": [
      "xlsx"
    ],
    "mimeTypes": [
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    ],
    "operations": [
      "export"
    ],
    "defaultOptions": [
      {
        "key": "qualityMode",
        "kind": "string",
        "stringValue": "balanced"
      },
      {
        "key": "missingFontPolicy",
        "kind": "string",
        "stringValue": "reject"
      }
    ],
    "availability": "planned"
  }
]; }
export function createRoutes(): ConversionRouteDefinition[] { return [
  {
    "id": "pdf-docx",
    "from": [
      "pdf"
    ],
    "to": "docx",
    "operation": "convert",
    "pathMode": "direct",
    "intent": "structured_rebuild",
    "fidelityTier": "compatible",
    "engineIds": [
      "pdf",
      "office"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 3,
    "steps": [
      {
        "stepId": "pdf-docx-1",
        "engineIds": [
          "pdf",
          "office"
        ],
        "inputFormatIds": [
          "pdf"
        ],
        "outputFormatId": "docx",
        "operation": "convert",
        "executorEngineId": "pdf"
      }
    ],
    "fallbackRouteIds": [],
    "requiresUserApproval": false,
    "allowedDegradations": [],
    "inputConstraints": {
      "minInputs": 1,
      "maxInputs": 1,
      "protectedInputs": "block"
    },
    "optionsProfileId": "office_rebuild",
    "validationProfileId": "office_structure"
  },
  {
    "id": "pdf-pptx",
    "from": [
      "pdf"
    ],
    "to": "pptx",
    "operation": "convert",
    "pathMode": "direct",
    "intent": "structured_rebuild",
    "fidelityTier": "compatible",
    "engineIds": [
      "pdf",
      "office"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 3,
    "steps": [
      {
        "stepId": "pdf-pptx-1",
        "engineIds": [
          "pdf",
          "office"
        ],
        "inputFormatIds": [
          "pdf"
        ],
        "outputFormatId": "pptx",
        "operation": "convert",
        "executorEngineId": "pdf"
      }
    ],
    "fallbackRouteIds": [],
    "requiresUserApproval": false,
    "allowedDegradations": [],
    "inputConstraints": {
      "minInputs": 1,
      "maxInputs": 1,
      "protectedInputs": "block"
    },
    "optionsProfileId": "office_rebuild",
    "validationProfileId": "office_structure"
  },
  {
    "id": "pdf-pptx-visual",
    "from": [
      "pdf"
    ],
    "to": "pptx",
    "operation": "convert",
    "pathMode": "direct",
    "intent": "layout_preserved",
    "fidelityTier": "standard",
    "engineIds": [
      "pdf",
      "image",
      "office"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 3,
    "steps": [
      {
        "stepId": "pdf-pptx-visual-1",
        "engineIds": [
          "pdf",
          "image",
          "office"
        ],
        "inputFormatIds": [
          "pdf"
        ],
        "outputFormatId": "pptx",
        "operation": "convert",
        "executorEngineId": "pdf"
      }
    ],
    "fallbackRouteIds": [],
    "requiresUserApproval": false,
    "allowedDegradations": [],
    "inputConstraints": {
      "minInputs": 1,
      "maxInputs": 1,
      "protectedInputs": "block"
    },
    "optionsProfileId": "office_rebuild",
    "validationProfileId": "office_layout"
  },
  {
    "id": "docx-pptx",
    "from": [
      "docx"
    ],
    "to": "pptx",
    "operation": "convert",
    "pathMode": "direct",
    "intent": "content_only",
    "fidelityTier": "compatible",
    "engineIds": [
      "office"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 3,
    "steps": [
      {
        "stepId": "docx-pptx-1",
        "engineIds": [
          "office"
        ],
        "inputFormatIds": [
          "docx"
        ],
        "outputFormatId": "pptx",
        "operation": "convert",
        "executorEngineId": "office"
      }
    ],
    "fallbackRouteIds": [],
    "requiresUserApproval": false,
    "allowedDegradations": [],
    "inputConstraints": {
      "minInputs": 1,
      "maxInputs": 1,
      "protectedInputs": "block"
    },
    "optionsProfileId": "office_content",
    "validationProfileId": "content"
  },
  {
    "id": "pptx-docx",
    "from": [
      "pptx"
    ],
    "to": "docx",
    "operation": "convert",
    "pathMode": "direct",
    "intent": "content_only",
    "fidelityTier": "compatible",
    "engineIds": [
      "office"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 3,
    "steps": [
      {
        "stepId": "pptx-docx-1",
        "engineIds": [
          "office"
        ],
        "inputFormatIds": [
          "pptx"
        ],
        "outputFormatId": "docx",
        "operation": "convert",
        "executorEngineId": "office"
      }
    ],
    "fallbackRouteIds": [],
    "requiresUserApproval": false,
    "allowedDegradations": [],
    "inputConstraints": {
      "minInputs": 1,
      "maxInputs": 1,
      "protectedInputs": "block"
    },
    "optionsProfileId": "office_content",
    "validationProfileId": "content"
  },
  {
    "id": "pdf-xlsx",
    "from": [
      "pdf"
    ],
    "to": "xlsx",
    "operation": "convert",
    "pathMode": "direct",
    "intent": "structured_rebuild",
    "fidelityTier": "compatible",
    "engineIds": [
      "pdf",
      "office"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 4,
    "steps": [
      {
        "stepId": "pdf-xlsx-1",
        "engineIds": [
          "pdf",
          "office"
        ],
        "inputFormatIds": [
          "pdf"
        ],
        "outputFormatId": "xlsx",
        "operation": "convert",
        "executorEngineId": "pdf"
      }
    ],
    "fallbackRouteIds": [],
    "requiresUserApproval": false,
    "allowedDegradations": [],
    "inputConstraints": {
      "minInputs": 1,
      "maxInputs": 1,
      "protectedInputs": "block"
    },
    "optionsProfileId": "pdf_table",
    "validationProfileId": "table"
  },
  {
    "id": "png-docx-ocr",
    "from": [
      "png"
    ],
    "to": "docx",
    "operation": "ocr_extract",
    "pathMode": "direct",
    "intent": "content_only",
    "fidelityTier": "compatible",
    "engineIds": [
      "image",
      "ocr",
      "office"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 4,
    "steps": [
      {
        "stepId": "png-docx-ocr-1",
        "engineIds": [
          "image",
          "ocr",
          "office"
        ],
        "inputFormatIds": [
          "png"
        ],
        "outputFormatId": "docx",
        "operation": "ocr_extract",
        "executorEngineId": "image"
      }
    ],
    "fallbackRouteIds": [],
    "requiresUserApproval": false,
    "allowedDegradations": [],
    "inputConstraints": {
      "minInputs": 1,
      "maxInputs": 1,
      "protectedInputs": "block"
    },
    "optionsProfileId": "ocr",
    "validationProfileId": "ocr"
  },
  {
    "id": "jpeg-docx-ocr",
    "from": [
      "jpeg"
    ],
    "to": "docx",
    "operation": "ocr_extract",
    "pathMode": "direct",
    "intent": "content_only",
    "fidelityTier": "compatible",
    "engineIds": [
      "image",
      "ocr",
      "office"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 4,
    "steps": [
      {
        "stepId": "jpeg-docx-ocr-1",
        "engineIds": [
          "image",
          "ocr",
          "office"
        ],
        "inputFormatIds": [
          "jpeg"
        ],
        "outputFormatId": "docx",
        "operation": "ocr_extract",
        "executorEngineId": "image"
      }
    ],
    "fallbackRouteIds": [],
    "requiresUserApproval": false,
    "allowedDegradations": [],
    "inputConstraints": {
      "minInputs": 1,
      "maxInputs": 1,
      "protectedInputs": "block"
    },
    "optionsProfileId": "ocr",
    "validationProfileId": "ocr"
  },
  {
    "id": "pdf-docx-ocr",
    "from": [
      "pdf"
    ],
    "to": "docx",
    "operation": "ocr_extract",
    "pathMode": "direct",
    "intent": "content_only",
    "fidelityTier": "compatible",
    "engineIds": [
      "pdf",
      "image",
      "ocr",
      "office"
    ],
    "priority": 10,
    "status": "planned",
    "phase": 4,
    "steps": [
      {
        "stepId": "pdf-docx-ocr-1",
        "engineIds": [
          "pdf",
          "image",
          "ocr",
          "office"
        ],
        "inputFormatIds": [
          "pdf"
        ],
        "outputFormatId": "docx",
        "operation": "ocr_extract",
        "executorEngineId": "pdf"
      }
    ],
    "fallbackRouteIds": [],
    "requiresUserApproval": false,
    "allowedDegradations": [],
    "inputConstraints": {
      "minInputs": 1,
      "maxInputs": 1,
      "protectedInputs": "block"
    },
    "optionsProfileId": "ocr",
    "validationProfileId": "ocr"
  }
]; }
