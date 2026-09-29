export interface PickedFile {
  uri: string;
  fileName: string;
  fileSize: number;
  mimeType: string;
}

export interface AuthorizedFile {
  fileId: string;
  originalName: string;
  relativePath: string;
  byteSize: number;
  sha256: string;
  detectedFormatId: string;
  mimeType: string;
  warnings?: string[];
}

// Local input ownership; Native session/workspace handles are obtained separately.
export interface SessionContext {
  sessionId: string;
  workspaceRef: string;
  createdAt: number;
  inputFiles: AuthorizedFile[];
}

export interface FileAuthorizationPlatform {
  isAvailable(): boolean;
  cacheDir(): string;
  uuid(): string;
  now(): number;
  pick(maxCount: number): Promise<PickedFile[]>;
  exists(path: string): Promise<boolean>;
  mkdir(path: string): Promise<void>;
  freeBytes(path: string): Promise<number>;
  copyUri(uri: string, destination: string, maxBytes: number, active: () => boolean): Promise<number>;
  sha256(path: string): Promise<string>;
  unlink(path: string): Promise<void>;
  removeDirectory(path: string): Promise<void>;
}
