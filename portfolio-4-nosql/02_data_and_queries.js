// 02_data_and_queries.js
// Small seed for member_documents and portal_activity, then 3 aggregation
// pipelines that answer typical PFA questions.
//
// Run with:   mongosh pensions 02_data_and_queries.js
// Requires:   01_setup.js already run.

db = db.getSiblingDB("pensions");

// Clean slate for the small seed rows only.
db.member_documents.deleteMany({});
db.portal_activity.deleteMany({});

// --- Seed: 8 member_documents, mix of BVN_VERIFICATION and CLAIM_FORM.
db.member_documents.insertMany([
  {
    _id: ObjectId(),
    rsa_number: "LHP/RSA/000001",
    document_type: "BVN_VERIFICATION",
    bvn: "12345678901",
    uploaded_at: new Date(Date.now() - 7 * 24 * 3600 * 1000),
    file_size_bytes: Int32(120_000),
    mime_type: "application/pdf",
    storage_key: "s3://lhp-docs/000001/bvn.pdf",
    status: "ACCEPTED",
    notes: "BVN matched with NIBSS"
  },
  {
    _id: ObjectId(),
    rsa_number: "LHP/RSA/000001",
    document_type: "CLAIM_FORM",
    claim_id: Long.fromString("1001"),
    claim_type: "EARLY",
    uploaded_at: new Date(Date.now() - 2 * 24 * 3600 * 1000),
    file_size_bytes: Int32(240_000),
    mime_type: "application/pdf",
    storage_key: "s3://lhp-docs/000001/claim-1001.pdf",
    status: "ACCEPTED",
    notes: "Signed early-withdrawal form"
  },
  {
    _id: ObjectId(),
    rsa_number: "LHP/RSA/000007",
    document_type: "CLAIM_FORM",
    claim_id: Long.fromString("1002"),
    claim_type: "EARLY",
    uploaded_at: new Date(Date.now() - 1 * 24 * 3600 * 1000),
    file_size_bytes: Int32(180_000),
    mime_type: "application/pdf",
    storage_key: "s3://lhp-docs/000007/claim-1002.pdf",
    status: "ACCEPTED"
  },
  {
    _id: ObjectId(),
    rsa_number: "LHP/RSA/000010",
    document_type: "CLAIM_FORM",
    claim_id: Long.fromString("1003"),
    claim_type: "RETIREMENT",
    uploaded_at: new Date(Date.now() - 30 * 24 * 3600 * 1000),
    file_size_bytes: Int32(310_000),
    mime_type: "application/pdf",
    storage_key: "s3://lhp-docs/000010/claim-1003.pdf",
    status: "ACCEPTED"
  },
  {
    _id: ObjectId(),
    rsa_number: "LHP/RSA/000002",
    document_type: "BVN_VERIFICATION",
    bvn: "12345678902",
    uploaded_at: new Date(Date.now() - 60 * 24 * 3600 * 1000),
    file_size_bytes: Int32(95_000),
    mime_type: "application/pdf",
    storage_key: "s3://lhp-docs/000002/bvn.pdf",
    status: "ACCEPTED"
  },
  {
    _id: ObjectId(),
    rsa_number: "LHP/RSA/000013",
    document_type: "CLAIM_FORM",
    claim_id: Long.fromString("1004"),
    claim_type: "RETIREMENT",
    uploaded_at: new Date(Date.now() - 5 * 24 * 3600 * 1000),
    file_size_bytes: Int32(260_000),
    mime_type: "application/pdf",
    storage_key: "s3://lhp-docs/000013/claim-1004.pdf",
    status: "ACCEPTED"
  },
  {
    _id: ObjectId(),
    rsa_number: "LHP/RSA/000013",
    document_type: "BVN_VERIFICATION",
    bvn: "12345678913",
    uploaded_at: new Date(Date.now() - 90 * 24 * 3600 * 1000),
    file_size_bytes: Int32(140_000),
    mime_type: "application/pdf",
    storage_key: "s3://lhp-docs/000013/bvn.pdf",
    status: "ACCEPTED"
  },
  {
    _id: ObjectId(),
    rsa_number: "LHP/RSA/000010",
    document_type: "BVN_VERIFICATION",
    bvn: "12345678910",
    uploaded_at: new Date(Date.now() - 120 * 24 * 3600 * 1000),
    file_size_bytes: Int32(110_000),
    mime_type: "application/pdf",
    storage_key: "s3://lhp-docs/000010/bvn.pdf",
    status: "ACCEPTED"
  }
]);

// --- Seed: 12 portal_activity events.
function daysAgo(n) { return new Date(Date.now() - n * 24 * 3600 * 1000); }
db.portal_activity.insertMany([
  { _id: ObjectId(), rsa_number: "LHP/RSA/000001", activity_type: "LOGIN",            occurred_at: daysAgo(1),  ip_address: "41.58.0.10",   login_method: "OTP",      status: "SUCCESS", duration_ms: Int32(320) },
  { _id: ObjectId(), rsa_number: "LHP/RSA/000001", activity_type: "STATEMENT_VIEW",   occurred_at: daysAgo(1),  ip_address: "41.58.0.10",   statement_period: "2024-09", status: "SUCCESS", duration_ms: Int32(410) },
  { _id: ObjectId(), rsa_number: "LHP/RSA/000002", activity_type: "LOGIN",            occurred_at: daysAgo(2),  ip_address: "105.112.0.7",  login_method: "PASSWORD", status: "SUCCESS", duration_ms: Int32(180) },
  { _id: ObjectId(), rsa_number: "LHP/RSA/000007", activity_type: "LOGIN",            occurred_at: daysAgo(3),  ip_address: "197.210.0.22", login_method: "OTP",      status: "SUCCESS", duration_ms: Int32(290) },
  { _id: ObjectId(), rsa_number: "LHP/RSA/000007", activity_type: "STATEMENT_VIEW",   occurred_at: daysAgo(3),  ip_address: "197.210.0.22", statement_period: "2024-08", status: "SUCCESS", duration_ms: Int32(500) },
  { _id: ObjectId(), rsa_number: "LHP/RSA/000010", activity_type: "LOGIN",            occurred_at: daysAgo(5),  ip_address: "41.58.0.41",   login_method: "PASSWORD", status: "SUCCESS", duration_ms: Int32(220) },
  { _id: ObjectId(), rsa_number: "LHP/RSA/000010", activity_type: "STATEMENT_VIEW",   occurred_at: daysAgo(5),  ip_address: "41.58.0.41",   statement_period: "2024-07", status: "SUCCESS", duration_ms: Int32(360) },
  { _id: ObjectId(), rsa_number: "LHP/RSA/000010", activity_type: "STATEMENT_VIEW",   occurred_at: daysAgo(4),  ip_address: "41.58.0.41",   statement_period: "2024-08", status: "SUCCESS", duration_ms: Int32(330) },
  { _id: ObjectId(), rsa_number: "LHP/RSA/000013", activity_type: "LOGIN",            occurred_at: daysAgo(6),  ip_address: "105.112.0.91", login_method: "OTP",      status: "SUCCESS", duration_ms: Int32(410) },
  { _id: ObjectId(), rsa_number: "LHP/RSA/000013", activity_type: "STATEMENT_VIEW",   occurred_at: daysAgo(6),  ip_address: "105.112.0.91", statement_period: "2024-09", status: "SUCCESS", duration_ms: Int32(440) },
  { _id: ObjectId(), rsa_number: "LHP/RSA/000002", activity_type: "STATEMENT_VIEW",   occurred_at: daysAgo(2),  ip_address: "105.112.0.7",  statement_period: "2024-09", status: "SUCCESS", duration_ms: Int32(280) },
  { _id: ObjectId(), rsa_number: "LHP/RSA/000001", activity_type: "LOGIN",            occurred_at: daysAgo(8),  ip_address: "41.58.0.10",   login_method: "PASSWORD", status: "SUCCESS", duration_ms: Int32(190) }
]);

print("02_data_and_queries.js: seed inserted: member_documents=" +
      db.member_documents.countDocuments() + ", portal_activity=" +
      db.portal_activity.countDocuments());

// =====================================================================
// Pipeline 1: per-RSA document counts split by document_type
// =====================================================================
print("\n--- Pipeline 1: document counts per RSA, split by document_type ---");
printjson(db.member_documents.aggregate([
  { $group: {
      _id: { rsa_number: "$rsa_number", document_type: "$document_type" },
      count: { $sum: 1 },
      last_uploaded: { $max: "$uploaded_at" }
  }},
  { $sort: { "_id.rsa_number": 1, "_id.document_type": 1 } }
]).toArray());

// =====================================================================
// Pipeline 2: portal activity in the last 7 days, per RSA,
// with separate counts of LOGIN vs STATEMENT_VIEW events.
// =====================================================================
print("\n--- Pipeline 2: last-7-day portal activity per RSA ---");
printjson(db.portal_activity.aggregate([
  { $match: { occurred_at: { $gte: daysAgo(7) } } },
  { $group: {
      _id: "$rsa_number",
      logins:    { $sum: { $cond: [{ $eq: ["$activity_type", "LOGIN"] }, 1, 0] } },
      statements:{ $sum: { $cond: [{ $eq: ["$activity_type", "STATEMENT_VIEW"] }, 1, 0] } },
      first_seen: { $min: "$occurred_at" },
      last_seen:  { $max: "$occurred_at" }
  }},
  { $sort: { logins: -1, statements: -1 } }
]).toArray());

// =====================================================================
// Pipeline 3: claim-form documents joined (via $lookup) to portal logins
// for the same RSA - which members uploaded a claim form AND logged in
// during the 7 days around the upload?
// =====================================================================
print("\n--- Pipeline 3: claim-form uploads that also had a portal login within +/- 7 days ---");
printjson(db.member_documents.aggregate([
  { $match: { document_type: "CLAIM_FORM" } },
  { $lookup: {
      from: "portal_activity",
      let: { rsa: "$rsa_number", up: "$uploaded_at" },
      pipeline: [
        { $match: {
            $expr: {
              $and: [
                { $eq: ["$rsa_number", "$$rsa"] },
                { $eq: ["$activity_type", "LOGIN"] },
                { $gte: ["$occurred_at", { $toDate: { $subtract: ["$$up", 7 * 24 * 3600 * 1000] } }] },
                { $lte: ["$occurred_at", { $toDate: { $add:      ["$$up", 7 * 24 * 3600 * 1000] } }] }
              ]
            }
        }},
        { $project: { _id: 0, occurred_at: 1, ip_address: 1, login_method: 1 } }
      ],
      as: "logins"
  }},
  { $match: { "logins.0": { $exists: true } } },
  { $project: {
      _id: 0,
      rsa_number: 1,
      claim_id: 1,
      claim_type: 1,
      uploaded_at: 1,
      logins: 1
  }},
  { $sort: { uploaded_at: -1 } }
]).toArray());

print("\n02_data_and_queries.js: done.");
