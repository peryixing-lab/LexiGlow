import { SelectionExtensionAbility, selectionManager } from '@kit.BasicServicesKit';
import { Want } from '@kit.AbilityKit';
import { rpc } from '@kit.IPCKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

class SelectionConnection extends rpc.RemoteObject {
  constructor() { super('com.lovexjy.lexiglow.WordSelectionAbility'); }

  onRemoteMessageRequest(code: number, data: rpc.MessageSequence, reply: rpc.MessageSequence,
    options: rpc.MessageOption): boolean {
    return false;
  }
}

/** Official API 24 word selection extension; supported on PC/2in1 only. */
export default class WordSelectionAbility extends SelectionExtensionAbility {
  private listening: boolean = false;
  private opening: boolean = false;
  private connected: boolean = false;
  private selectionCallback: (info: selectionManager.SelectionInfo) => void =
    (info: selectionManager.SelectionInfo): void => { this.openPreview(); };

  onConnect(want: Want): rpc.RemoteObject {
    this.connected = true;
    if (!this.listening && canIUse('SystemCapability.SelectionInput.Selection')) {
      try {
        selectionManager.on('selectionCompleted', this.selectionCallback);
        this.listening = true;
      } catch (_) {
        hilog.warn(0x0000, 'Ciying', 'Word selection service is unavailable');
      }
    }
    return new SelectionConnection();
  }

  private async openPreview(): Promise<void> {
    if (this.opening || !this.connected) { return; }
    this.opening = true;
    try {
      const text = (await selectionManager.getSelectionContent()).trim().slice(0, 4096);
      if (!this.connected || !/[A-Za-z]/.test(text)) { return; }
      await this.context.startAbility({
        bundleName: 'com.lovexjy.lexiglow',
        abilityName: 'EntryAbility',
        parameters: { route: 'shared', lexiglowSharedText: text }
      });
    } catch (_) {
      hilog.warn(0x0000, 'Ciying', 'Could not open word selection preview');
    } finally {
      this.opening = false;
    }
  }

  onDisconnect(): void {
    this.connected = false;
    if (this.listening) {
      selectionManager.off('selectionCompleted', this.selectionCallback);
      this.listening = false;
    }
  }
}
