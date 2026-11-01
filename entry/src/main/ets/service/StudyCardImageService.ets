import { UIContext } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { fileIo, picker } from '@kit.CoreFileKit';

/** Snapshot only the visible card; the picker grants access to the selected destination. */
export class StudyCardImageService {
  static async save(uiContext: UIContext, componentId: string, date: string): Promise<boolean> {
    let pixelMap: image.PixelMap | undefined = undefined;
    let packer: image.ImagePacker | undefined = undefined;
    let bytes: ArrayBuffer;
    try {
      pixelMap = await uiContext.getComponentSnapshot().get(componentId);
      packer = image.createImagePacker();
      bytes = await packer.packing(pixelMap, { format: 'image/png', quality: 100 });
    } finally {
      try { if (packer) { await packer.release(); } }
      finally { if (pixelMap) { await pixelMap.release(); } }
    }
    const context = uiContext.getHostContext() as common.UIAbilityContext;
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [`词萤今日学习_${date.replace(/[^0-9-]/g, '') || '今日'}.png`];
    options.fileSuffixChoices = ['PNG 图片|.png'];
    const uris = await new picker.DocumentViewPicker(context).save(options);
    if (uris.length === 0) { return false; }
    const file = await fileIo.open(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      let offset = 0;
      while (offset < bytes.byteLength) {
        const count = await fileIo.write(file.fd, bytes.slice(offset));
        if (count <= 0) { throw new Error('学习卡片未能完整保存，请重试'); }
        offset += count;
      }
    } finally { await fileIo.close(file); }
    return true;
  }
}
