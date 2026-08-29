import QtQuick
import QtTest
import "../GmailUnread.js" as GmailUnread

TestCase {
    name: "GmailUnread"

    function expectParseFailure(value) {
        let failed = false;
        try {
            GmailUnread.parsePayload(JSON.stringify(value));
        } catch (error) {
            failed = true;
        }
        verify(failed);
    }

    function payload() {
        return {
            configured: true,
            countField: "threadsUnread",
            total: 9,
            accounts: [
                {
                    name: "Personal",
                    total: 7,
                    labels: [
                        { id: "INBOX", name: "Inbox", unread: 5 },
                        { id: "Label_42", name: "Receipts", unread: 2 }
                    ]
                },
                {
                    name: "Work",
                    total: 2,
                    labels: [
                        { id: "INBOX", name: "Inbox", unread: 2 }
                    ]
                }
            ]
        };
    }

    function test_periodicRefreshInterval() {
        compare(GmailUnread.periodicRefreshIntervalMs(), 60000);
    }

    function test_parseMultiAccountMultiLabelPayload() {
        const parsed = GmailUnread.parsePayload(JSON.stringify(payload()));
        verify(parsed.configured);
        compare(parsed.total, 9);
        compare(parsed.accounts.length, 2);
        compare(parsed.accounts[0].labels.length, 2);
        compare(parsed.accounts[1].labels[0].unread, 2);
    }

    function test_parseDisabledPayload() {
        const parsed = GmailUnread.parsePayload('{"configured":false}');
        verify(!parsed.configured);
        compare(parsed.total, 0);
        compare(parsed.accounts.length, 0);
    }

    function test_rejectMismatchedTotals() {
        const value = payload();
        value.total = 8;
        expectParseFailure(value);

        value.total = 9;
        value.accounts[0].total = 6;
        expectParseFailure(value);
    }

    function test_rejectInvalidCounts() {
        const value = payload();
        value.accounts[0].labels[0].unread = -1;
        expectParseFailure(value);
    }

    function test_badgeText() {
        compare(GmailUnread.badgeText(0), "0");
        compare(GmailUnread.badgeText(42), "42");
        compare(GmailUnread.badgeText(100), "99+");
    }

    function test_tooltipBreakdownAndOverlapWarning() {
        const text = GmailUnread.tooltip(payload());
        verify(text.indexOf("Personal · 7") >= 0);
        verify(text.indexOf("Receipts · 2") >= 0);
        verify(text.indexOf("Work · 2") >= 0);
        verify(text.indexOf("overlapping labels") >= 0);
    }
}
