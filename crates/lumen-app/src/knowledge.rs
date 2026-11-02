//! The shared built-in developer knowledge base.

use std::sync::OnceLock;

use lumen_devkb::KnowledgeBase;

/// The built-in knowledge base, loaded once; `None` if it does not load.
pub(crate) fn builtin_knowledge_base() -> Option<&'static KnowledgeBase> {
    static KNOWLEDGE_BASE: OnceLock<Option<KnowledgeBase>> = OnceLock::new();
    KNOWLEDGE_BASE
        .get_or_init(|| KnowledgeBase::builtin().ok())
        .as_ref()
}
