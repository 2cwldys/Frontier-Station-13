#define WEBHOOK_ADMIN_PM "g_apm"
#define WEBHOOK_ADMIN_PM_IMPORTANT "g_apm_a"
#define WEBHOOK_ADMIN "g_admin"
#define WEBHOOK_ADMIN_IMPORTANT "g_admin_a"
#define WEBHOOK_CCIAA_EMERGENCY_MESSAGE "cciaa_emergency"
#define WEBHOOK_ALERT_NO_ADMINS "alert_noadmins"
#define WEBHOOK_ROUNDEND "roundend"
#define WEBHOOK_ROUNDSTART "roundstart"
#define WEBHOOK_ADMIN_LOG "admin_log"
/// Security feed: everything a law-enforcement team acts on -- highsec
/// offenses and distress calls at the moment they hit responders' PDAs, plus
/// the First Responder enforcement actions that follow (repossession,
/// force-stash, scuttling, schematic withdrawal, stolen-flag clearing).
/// Separate from WEBHOOK_ADMIN_LOG so that channel gets the security picture
/// without being handed the whole admin log -- add a webhook carrying this
/// tag to config/webhooks.json (or ss13_webhooks). Role pinging is configured
/// on the Discord side via the entry's "mention" field, not here.
#define WEBHOOK_LAW_ENFORCEMENT "law_enforcement"
