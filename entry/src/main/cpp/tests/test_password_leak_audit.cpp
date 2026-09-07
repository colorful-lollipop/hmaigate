// test_password_leak_audit.cpp —— 请求侧密码泄露提醒的宿主侧测试
//
// 审计器只断言脱敏元数据，测试不会输出或比较任何可能的凭据正文。
#include "../include/security/password_leak_audit.h"
#include "hm_test.h"

#include <string>

using aigate::PasswordLeakAlert;
using aigate::PasswordLeakAudit;
using aigate::PasswordLeakAlertPage;

static PasswordLeakAlertPage AlertsAfter(const std::string& body,
                                         const std::string& protocol = "anthropic",
                                         const std::string& model = "claude-test") {
  PasswordLeakAudit& audit = PasswordLeakAudit::GetInstance();
  audit.ClearAlerts();
  audit.SetEnabled(true);
  audit.Enqueue(body, protocol, model);
  EQ_BOOL(audit.WaitForIdleForTest(2000), true);
  return audit.GetAlerts(0, 100);
}

static bool HasAlert(const PasswordLeakAlertPage& page, const std::string& secretType,
                     const std::string& location) {
  for (const PasswordLeakAlert& alert : page.alerts) {
    if (alert.secretType == secretType && alert.location == location) return true;
  }
  return false;
}

static void test_json_password_generates_metadata_only_alert() {
  PasswordLeakAlertPage page = AlertsAfter("{\"password\":\"local-value-42\"}");
  EQ_BOOL(page.total > 0, true);
  EQ_BOOL(HasAlert(page, "password", "json_field"), true);
  if (page.alerts.empty()) return;
  const PasswordLeakAlert& alert = page.alerts[0];
  EQ_STR(alert.severity, "medium");
  EQ_STR(alert.protocol, "anthropic");
  EQ_STR(alert.model, "claude-test");
  EQ_STR(alert.status, "new");
  // Alert 结构没有 message/value 字段；id 也只由时间和递增序号构成。
  EQ_BOOL(alert.id.find("local-value-42") == std::string::npos, true);
}

static void test_env_and_shell_assignments_are_detected() {
  PasswordLeakAlertPage envPage = AlertsAfter("OPENAI_API_KEY=local-key-value-123456789");
  EQ_BOOL(HasAlert(envPage, "api_key", "env_assignment"), true);

  PasswordLeakAlertPage shellPage = AlertsAfter("export passwd='local-shell-value'");
  EQ_BOOL(HasAlert(shellPage, "password", "env_assignment"), true);
}

static void test_known_key_formats_and_private_key_are_detected() {
  PasswordLeakAlertPage keyPage = AlertsAfter("sk-ant-abcdefghijklmnopqrstuvwx1234567890");
  EQ_BOOL(HasAlert(keyPage, "api_key", "known_pattern"), true);

  PasswordLeakAlertPage pemPage = AlertsAfter("-----BEGIN PRIVATE KEY-----\nnot-a-real-key");
  EQ_BOOL(HasAlert(pemPage, "private_key", "known_pattern"), true);
}

static void test_discussion_and_placeholders_do_not_alert() {
  PasswordLeakAlertPage discussion = AlertsAfter("如何在 .env 文件中设置 API_KEY？");
  EQ_INT(discussion.total, 0);

  PasswordLeakAlertPage placeholders = AlertsAfter(
      "password=YOUR_PASSWORD\napi_key=<token>\nsecret=REDACTED\ntoken=***");
  EQ_INT(placeholders.total, 0);
}

static void test_mark_read_clear_and_disable() {
  PasswordLeakAudit& audit = PasswordLeakAudit::GetInstance();
  PasswordLeakAlertPage page = AlertsAfter("token=local-token-value");
  EQ_BOOL(page.alerts.empty(), false);
  if (page.alerts.empty()) return;
  const uint32_t changed = audit.MarkRead({page.alerts[0].id});
  EQ_INT(changed, 1);
  PasswordLeakAlertPage readPage = audit.GetAlerts(0, 100);
  EQ_STR(readPage.alerts[0].status, "read");
  audit.ClearAlerts();
  EQ_INT(audit.GetAlerts(0, 100).total, 0);

  audit.SetEnabled(false);
  audit.Enqueue("password=should-not-be-audited", "openai", "gpt-test");
  EQ_BOOL(audit.WaitForIdleForTest(2000), true);
  EQ_INT(audit.GetAlerts(0, 100).total, 0);
  audit.SetEnabled(true);
}

static void test_truncated_body_is_accounted_without_alert_history_content() {
  PasswordLeakAudit& audit = PasswordLeakAudit::GetInstance();
  audit.ClearAlerts();
  const uint32_t before = audit.GetStatus().truncatedTasks;
  std::string body(256 * 1024 + 1, 'a');
  audit.Enqueue(body, "openai", "gpt-test");
  EQ_BOOL(audit.WaitForIdleForTest(2000), true);
  EQ_BOOL(audit.GetStatus().truncatedTasks >= before + 1, true);
  EQ_INT(audit.GetAlerts(0, 100).total, 0);
}

int main() {
  RUN_TEST(test_json_password_generates_metadata_only_alert);
  RUN_TEST(test_env_and_shell_assignments_are_detected);
  RUN_TEST(test_known_key_formats_and_private_key_are_detected);
  RUN_TEST(test_discussion_and_placeholders_do_not_alert);
  RUN_TEST(test_mark_read_clear_and_disable);
  RUN_TEST(test_truncated_body_is_accounted_without_alert_history_content);
  SUMMARY();
}
