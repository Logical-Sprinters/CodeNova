/// Hand-written models, one per shape the API returns.
///
/// No code generation: two extra build steps cost more than eight small
/// fromJson methods, and a codegen failure at 2am costs more than both.
class User {
  User(this.id, this.name, this.role, this.email);

  final String id;
  final String name;
  final String role;
  final String email;

  factory User.fromJson(Map<String, dynamic> j) => User(
        j['user_id'] as String,
        j['display_name'] as String,
        j['role'] as String,
        j['email'] as String? ?? '',
      );
}

class Rewrite {
  Rewrite(this.label, this.strategy, this.text, this.accepted);

  final String label;
  final String strategy;
  final String text;
  final bool accepted;

  factory Rewrite.fromJson(Map<String, dynamic> j) => Rewrite(
        j['option_label'] as String,
        j['strategy'] as String,
        j['rewrite_text'] as String,
        j['accepted'] as bool? ?? false,
      );
}

class Finding {
  Finding({
    required this.id,
    required this.status,
    required this.ruleId,
    required this.ruleVersion,
    required this.quote,
    required this.spanStart,
    required this.spanEnd,
    required this.message,
    required this.action,
    required this.ruleText,
    required this.sourceFile,
    required this.sourcePage,
    required this.ruleExpires,
    required this.overrideCount,
    required this.rewrites,
  });

  final String id;
  final String status;
  final String ruleId;
  final int ruleVersion;
  final String quote;
  final int? spanStart;
  final int? spanEnd;
  final String message;
  final String action;
  final String ruleText;
  final String sourceFile;
  final int? sourcePage;
  final String? ruleExpires;
  final int overrideCount;
  final List<Rewrite> rewrites;

  bool get blocksApproval =>
      (status == 'CONFIRMED_RULE_MATCH' || status == 'SOURCE_CONFLICT_OR_EXPIRED') &&
      overrideCount == 0;

  factory Finding.fromJson(Map<String, dynamic> j) => Finding(
        id: j['finding_id'] as String,
        status: j['status'] as String,
        ruleId: j['rule_id'] as String,
        ruleVersion: j['rule_version'] as int,
        quote: j['evidence_quote'] as String? ?? '',
        spanStart: j['span_start'] as int?,
        spanEnd: j['span_end'] as int?,
        message: j['message'] as String,
        action: j['action'] as String,
        ruleText: j['rule_text'] as String? ?? '',
        sourceFile: j['source_file'] as String? ?? '',
        sourcePage: j['source_page'] as int?,
        ruleExpires: j['expires_on']?.toString(),
        overrideCount: (j['override_count'] as num? ?? 0).toInt(),
        rewrites: ((j['rewrites'] as List?) ?? const <dynamic>[])
            .map((dynamic e) => Rewrite.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class Approval {
  Approval(this.state, this.hash, this.approvedAt, this.voidedAt, this.voidReason);

  final String state;
  final String hash;
  final String? approvedAt;
  final String? voidedAt;
  final String? voidReason;

  static Approval? maybe(Map<String, dynamic>? j) {
    if (j == null) return null;
    return Approval(
      j['state'] as String,
      j['content_hash'] as String? ?? '',
      j['approved_at']?.toString(),
      j['voided_at']?.toString(),
      j['void_reason'] as String?,
    );
  }
}

class ContentDetail {
  ContentDetail({
    required this.id,
    required this.title,
    required this.channel,
    required this.creator,
    required this.versionNumber,
    required this.text,
    required this.hash,
    required this.findings,
    required this.approval,
    required this.checkOutcome,
  });

  final String id;
  final String? title;
  final String channel;
  final String creator;
  final int versionNumber;
  final String text;
  final String hash;
  final List<Finding> findings;
  final Approval? approval;
  final String? checkOutcome;

  factory ContentDetail.fromJson(Map<String, dynamic> j) {
    final Map<String, dynamic> version = j['version'] as Map<String, dynamic>;
    final Map<String, dynamic>? run = j['check_run'] as Map<String, dynamic>?;
    return ContentDetail(
      id: j['content_id'] as String,
      title: j['title'] as String?,
      channel: j['channel'] as String,
      creator: j['creator'] as String,
      versionNumber: version['version_number'] as int,
      text: version['content_text'] as String,
      hash: version['canonical_hash'] as String,
      findings: ((j['findings'] as List?) ?? const <dynamic>[])
          .map((dynamic e) => Finding.fromJson(e as Map<String, dynamic>))
          .toList(),
      approval: Approval.maybe(j['approval'] as Map<String, dynamic>?),
      checkOutcome: run == null ? null : run['outcome'] as String?,
    );
  }
}

class ContentSummary {
  ContentSummary({
    required this.id,
    required this.title,
    required this.channel,
    required this.creator,
    required this.versionNumber,
    required this.hash,
    required this.text,
    required this.approvalState,
    required this.blocking,
    required this.total,
  });

  final String id;
  final String? title;
  final String channel;
  final String creator;
  final int versionNumber;
  final String hash;
  final String text;
  final String? approvalState;
  final int blocking;
  final int total;

  factory ContentSummary.fromJson(Map<String, dynamic> j) => ContentSummary(
        id: j['content_id'] as String,
        title: j['title'] as String?,
        channel: j['channel'] as String,
        creator: j['creator'] as String,
        versionNumber: j['version_number'] as int,
        hash: j['canonical_hash'] as String,
        text: j['content_text'] as String? ?? '',
        approvalState: j['approval_state'] as String?,
        blocking: (j['blocking_findings'] as num? ?? 0).toInt(),
        total: (j['total_findings'] as num? ?? 0).toInt(),
      );
}

class QueueItem {
  QueueItem({
    required this.id,
    required this.channel,
    required this.creator,
    required this.versionNumber,
    required this.text,
    required this.advisory,
    required this.approvalState,
  });

  final String id;
  final String channel;
  final String creator;
  final int versionNumber;
  final String text;
  final int advisory;
  final String? approvalState;

  factory QueueItem.fromJson(Map<String, dynamic> j) => QueueItem(
        id: j['content_id'] as String,
        channel: j['channel'] as String,
        creator: j['creator'] as String,
        versionNumber: j['version_number'] as int,
        text: j['content_text'] as String? ?? '',
        advisory: (j['advisory_findings'] as num? ?? 0).toInt(),
        approvalState: j['approval_state'] as String?,
      );
}

class LedgerEntry {
  LedgerEntry({
    required this.id,
    required this.actorType,
    required this.actor,
    required this.action,
    required this.reason,
    required this.details,
    required this.occurredAt,
    required this.channel,
    required this.contentId,
  });

  final String id;
  final String actorType;
  final String? actor;
  final String action;
  final String? reason;
  final Map<String, dynamic> details;
  final String occurredAt;
  final String channel;
  final String contentId;

  factory LedgerEntry.fromJson(Map<String, dynamic> j) => LedgerEntry(
        id: j['entry_id'] as String,
        actorType: j['actor_type'] as String,
        actor: j['actor'] as String?,
        action: j['action'] as String,
        reason: j['reason'] as String?,
        details: (j['details'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
        occurredAt: j['occurred_at'].toString(),
        channel: j['channel'] as String? ?? '',
        contentId: j['content_id'] as String,
      );
}

class Rule {
  Rule({
    required this.id,
    required this.version,
    required this.type,
    required this.text,
    required this.status,
    required this.effectiveFrom,
    required this.expiresOn,
    required this.sourceFile,
    required this.sourcePage,
    required this.isLive,
    required this.channels,
    required this.priceSensitive,
  });

  final String id;
  final int version;
  final String type;
  final String text;
  final String status;
  final String effectiveFrom;
  final String? expiresOn;
  final String sourceFile;
  final int? sourcePage;
  final bool isLive;
  final List<String> channels;
  final bool priceSensitive;

  factory Rule.fromJson(Map<String, dynamic> j) => Rule(
        id: j['rule_id'] as String,
        version: j['version'] as int,
        type: j['type'] as String,
        text: j['rule_text'] as String,
        status: j['status'] as String,
        effectiveFrom: j['effective_from'].toString(),
        expiresOn: j['expires_on']?.toString(),
        sourceFile: j['source_file'] as String? ?? '',
        sourcePage: j['source_page'] as int?,
        isLive: j['is_live_now'] as bool? ?? false,
        channels: ((j['channels'] as List?) ?? const <dynamic>[])
            .map((dynamic e) => e.toString())
            .toList(),
        priceSensitive: j['price_sensitive'] as bool? ?? false,
      );
}
