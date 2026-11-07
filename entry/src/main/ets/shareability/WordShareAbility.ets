import { ShareExtensionAbility, UIExtensionContentSession, Want } from '@kit.AbilityKit';
import { LexiNoteBridgeService } from '../service/LexiNoteBridgeService';

/** Official system sharing target. The share page forwards only after a user's tap. */
export default class WordShareAbility extends ShareExtensionAbility {
  private sessions: UIExtensionContentSession[] = [];

  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    this.sessions.push(session);
    this.prepare(want, session);
  }

  private async prepare(want: Want, session: UIExtensionContentSession): Promise<void> {
    const resolved = await LexiNoteBridgeService.resolveSharedWant(want);
    if (this.sessions.indexOf(session) < 0) { return; }
    const storage = new LocalStorage();
    storage.setOrCreate('sharedTitle', resolved.title);
    storage.setOrCreate('sharedText', resolved.body);
    storage.setOrCreate('shareSession', session);
    session.loadContent('pages/SharedWordPage', storage);
  }

  onSessionDestroy(session: UIExtensionContentSession): void {
    this.sessions = this.sessions.filter((active: UIExtensionContentSession): boolean => active !== session);
  }
}
