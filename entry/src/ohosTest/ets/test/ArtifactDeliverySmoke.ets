import { common } from '@kit.AbilityKit';
import { fileIo, hash, picker } from '@kit.CoreFileKit';
import { Driver } from '@ohos.UiTest';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { expect } from '@ohos/hypium';
import { Artifact } from '../../../main/ets/models/NativeProtocol';
import { ArtifactDelivery } from '../../../main/ets/services/ArtifactDelivery';
import { NativeBridgeService } from '../../../main/ets/services/NativeBridge';
import { TaskStore } from '../../../main/ets/viewmodel/TaskStore';

// Isolate delivery from scheduling; the artifact and copy operation use the real Native engine.
class DeliverySmokeStore extends TaskStore {
  private output: Artifact;
  exported: boolean = false;
  shared: boolean = false;
  constructor(output: Artifact) { super(); this.output = output; }
  beginExport(taskId: string): Artifact { return this.output; }
  beginShare(taskId: string): Artifact { return this.output; }
  finishExport(taskId: string, artifactId: string, state: 'exported' | 'failed' | 'cancelled'): void {
    this.exported = state === 'exported';
  }
  finishShare(taskId: string, shown: boolean): void { this.shared = shown; }
}

export async function artifactDeliverySmoke(native: NativeBridgeService, output: Artifact,
  context: common.UIAbilityContext): Promise<void> {
  const store = new DeliverySmokeStore(output);
  const delivery = new ArtifactDelivery(store, native);
  hilog.info(0x0000, 'JpegDeliverySmoke', 'SAVE_START');
  const saved = await delivery.save('delivery-smoke', context);
  expect(saved).assertTrue();
  expect(store.exported).assertTrue();
  hilog.info(0x0000, 'JpegDeliverySmoke', 'SAVE_PASSED');
  await delivery.share('delivery-smoke', context);
  expect(store.shared).assertTrue();
  const sharedPath = context.cacheDir + '/shared-pdf/' + output.artifactId + '.pdf';
  expect((await hash.hash(sharedPath, 'sha256')).toLowerCase()).assertEqual(output.sha256);
  hilog.info(0x0000, 'JpegDeliverySmoke', 'SHARE_PASSED');
  const driver = Driver.create();
  await driver.delayMs(15000);
  await driver.pressBack();
  // Select only the synthetic PDF just saved, then compare every byte with the verified copy.
  hilog.info(0x0000, 'JpegDeliverySmoke', 'SELECT_SAVED_PDF_FOR_READBACK');
  const options = new picker.DocumentSelectOptions();
  options.maxSelectNumber = 1;
  options.fileSuffixFilters = ['.pdf'];
  const uris = await new picker.DocumentViewPicker(context).select(options);
  expect(uris.length).assertEqual(1);
  const savedFile = await fileIo.open(uris[0], fileIo.OpenMode.READ_ONLY);
  const sharedFile = await fileIo.open(sharedPath, fileIo.OpenMode.READ_ONLY);
  try {
    expect((await fileIo.stat(savedFile.fd)).size).assertEqual(output.byteSize);
    const savedBytes = new ArrayBuffer(output.byteSize);
    const expectedBytes = new ArrayBuffer(output.byteSize);
    expect(await fileIo.read(savedFile.fd, savedBytes)).assertEqual(output.byteSize);
    expect(await fileIo.read(sharedFile.fd, expectedBytes)).assertEqual(output.byteSize);
    const savedData = new Uint8Array(savedBytes);
    const expectedData = new Uint8Array(expectedBytes);
    expect(savedData.every((value: number, index: number) => value === expectedData[index])).assertTrue();
    hilog.info(0x0000, 'JpegDeliverySmoke', 'PUBLIC_PDF_READBACK_IDENTICAL=%{public}s', output.sha256);
  } finally { await fileIo.close(savedFile); await fileIo.close(sharedFile); }
}
