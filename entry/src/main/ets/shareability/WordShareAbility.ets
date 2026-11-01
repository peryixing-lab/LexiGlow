import { ShareExtensionAbility, UIExtensionContentSession, Want } from '@kit.AbilityKit';
import { SharedWordService } from '../service/SharedWordService';

/** Official system sharing target. The share page forwards only after a user's tap. */
export default class WordShareAbility extends ShareExtensionAbility {
  private sessions: UIExtensionContentSession[] = [];

  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    this.sessions.push(session);
    this.prepare(want, session);
  }

  private async prepare(want: Want, session: UIExtensionContentSession): Promise<void> {
    let text = '';
    try { text = await SharedWordService.textFromWant(want); } catch (_) {}
    if (this.sessions.indexOf(session) < 0) { return; }
    const storage = new LocalStorage();
    storage.setOrCreate('sharedText', text);
    storage.setOrCreate('shareSession', session);
    session.loadContent('pages/SharedWordPage', storage);
  }

  onSessionDestroy(session: UIExtensionContentSession): void {
    this.sessions = this.sessions.filter((active: UIExtensionContentSession): boolean => active !== session);
  }
}
