import { Want } from '@kit.AbilityKit';
import { FormExtensionAbility, formBindingData, formInfo } from '@kit.FormKit';
import { FormService } from '../service/FormService';
import { LearningService } from '../service/LearningService';

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId = want.parameters?.[formInfo.FormParam.IDENTITY_KEY] as string;
    if (formId) {
      FormService.register(this.context, formId);
    }
    const binding = FormService.binding(this.context);
    this.refresh();
    return binding;
  }

  onCastToNormalForm(formId: string): void {
    FormService.register(this.context, formId);
  }

  onUpdateForm(_formId: string): void {
    this.refresh();
  }

  onRemoveForm(formId: string): void {
    FormService.remove(this.context, formId);
  }

  onAcquireFormState(_want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }

  private async refresh(): Promise<void> {
    try {
      const service = LearningService.getInstance();
      await service.initialize(this.context);
      const snapshot = await service.getSnapshot();
      await FormService.update(snapshot, this.context);
    } catch (error) {
      console.warn(`词萤卡片保留本地快照: ${String(error)}`);
    }
  }
}
