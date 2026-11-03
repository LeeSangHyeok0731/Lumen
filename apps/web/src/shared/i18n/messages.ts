import type { AiNoteView, ReasonView } from "@lumen/api-client";
import { en, type Messages } from "./en";
import { es } from "./es";
import { ja } from "./ja";
import { ko } from "./ko";
import type { Locale } from "./locale";
import { ru } from "./ru";
import { LOCATION_RULE_PREFIX, RULE_IDS } from "./rules";
import { zhCN } from "./zh-CN";

/** Every locale's catalog. */
export const MESSAGES: { readonly [L in Locale]: Messages } = {
  en,
  ko,
  ru,
  ja,
  "zh-CN": zhCN,
  es,
};

/**
 * One policy reason in the catalog's language, chosen by its stable rule ID.
 * A rule this UI does not know keeps the server's (English) sentence.
 */
export function reasonText(messages: Messages, reason: ReasonView): string {
  if (reason.rule.startsWith(LOCATION_RULE_PREFIX)) {
    return messages.reasons.location(reason.rule.slice(LOCATION_RULE_PREFIX.length));
  }
  const rule = RULE_IDS.find((id) => id === reason.rule);
  return rule === undefined ? reason.text : messages.reasons.rules[rule];
}

/**
 * An AI note on a review item (ADR-0041), labelled as AI: only the closed
 * kind and confidence from the API, never model text.
 */
export function aiNoteText(messages: Messages, note: AiNoteView): string {
  if (note.kind === "unknown") {
    return messages.aiNote.unknown;
  }
  return messages.aiNote.likely(
    messages.aiNote.kinds[note.kind],
    messages.aiNote.confidence[note.confidence],
  );
}
