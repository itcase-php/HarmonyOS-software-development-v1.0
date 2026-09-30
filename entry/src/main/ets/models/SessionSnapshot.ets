// Explicit DTO ownership snapshots. Update with the schema; coverage checks detect omissions.
import { PickedFile, AuthorizedFile, SessionContext } from './SessionModels';

export class SessionSnapshot {
  static copyPickedFile(value: PickedFile): PickedFile {
    const copy: PickedFile = {
      uri: value.uri,
      fileName: value.fileName,
      fileSize: value.fileSize,
      mimeType: value.mimeType
    };
    return copy;
  }
  static copyAuthorizedFile(value: AuthorizedFile): AuthorizedFile {
    const copy: AuthorizedFile = {
      fileId: value.fileId,
      originalName: value.originalName,
      relativePath: value.relativePath,
      byteSize: value.byteSize,
      sha256: value.sha256,
      detectedFormatId: value.detectedFormatId,
      mimeType: value.mimeType
    };
    const fields: string[] = Object.keys(value);
    if (fields.includes('warnings')) { copy.warnings = value.warnings === undefined ? undefined : value.warnings.slice(); }
    return copy;
  }
  static copySessionContext(value: SessionContext): SessionContext {
    const copy: SessionContext = {
      sessionId: value.sessionId,
      workspaceRef: value.workspaceRef,
      createdAt: value.createdAt,
      inputFiles: value.inputFiles.map((item: AuthorizedFile): AuthorizedFile => SessionSnapshot.copyAuthorizedFile(item))
    };
    return copy;
  }
}
