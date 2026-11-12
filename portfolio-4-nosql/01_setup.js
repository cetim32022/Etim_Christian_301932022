// 01_setup.js
// MongoDB 7+ setup for the pensions database.
// Creates two collections with $jsonSchema validators:
//   - member_documents : flexible KYC and claim documents per RSA holder
//   - portal_activity : member login and statement-view logs
//
// Run with:   mongosh pensions 01_setup.js
//
// Validator rules followed per the brief:
//   * enum with ONE value (not const) for status fields that we may extend later
//   * no if/then/else inside the schema
//   * oneOf used for the discriminated "document_type" shapes
//   * additionalProperties:false wherever used, with _id AND every field listed
//   * numbers wrapped in Double() / Int32()
//   * use db = db.getSiblingDB("pensions")  (not `use db;`)

db = db.getSiblingDB("pensions");

// Drop the two collections so the file is idempotent.
db.member_documents.drop();
db.portal_activity.drop();

// =====================================================================
// Collection 1: member_documents
// One document = one piece of KYC / claim paperwork for one RSA holder.
// Two document_type shapes via oneOf: "BVN_VERIFICATION" and "CLAIM_FORM".
// =====================================================================
db.createCollection("member_documents", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      title: "Member document",
      required: ["_id", "rsa_number", "document_type", "uploaded_at", "file_size_bytes", "status"],
      additionalProperties: false,
      properties: {
        _id:               { bsonType: "objectId" },
        rsa_number:        { bsonType: "string", minLength: 1, maxLength: 40 },
        document_type:     { bsonType: "string" },
        uploaded_at:       { bsonType: "date" },
        file_size_bytes:   { bsonType: "int", minimum: 0 },
        mime_type:         { bsonType: "string" },
        storage_key:       { bsonType: "string" },
        // status has ONE enum value today - extensible tomorrow.
        status:            { enum: ["ACCEPTED"] },
        notes:             { bsonType: "string", maxLength: 500 },
        // fields used by the oneOf branches must also be listed here because
        // additionalProperties is false
        bvn:               { bsonType: "string" },
        claim_id:          { bsonType: "long" },
        claim_type:        { bsonType: "string" }
      },
      oneOf: [
        {
          properties: {
            document_type: { enum: ["BVN_VERIFICATION"] },
            bvn:           { bsonType: "string", minLength: 11, maxLength: 11 }
          },
          required: ["bvn"]
        },
        {
          properties: {
            document_type: { enum: ["CLAIM_FORM"] },
            claim_id:      { bsonType: "long" },
            claim_type:    { enum: ["RETIREMENT","EARLY","INVOLUNTARY","DEATH"] }
          },
          required: ["claim_id", "claim_type"]
        }
      ]
    }
  },
  validationLevel: "strict",
  validationAction: "error"
});

// =====================================================================
// Collection 2: portal_activity
// One document = one member login OR one statement-view event.
// =====================================================================
db.createCollection("portal_activity", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      title: "Portal activity event",
      required: ["_id", "rsa_number", "activity_type", "occurred_at", "ip_address", "status"],
      additionalProperties: false,
      properties: {
        _id:            { bsonType: "objectId" },
        rsa_number:     { bsonType: "string", minLength: 1, maxLength: 40 },
        activity_type:  { bsonType: "string" },
        occurred_at:    { bsonType: "date" },
        ip_address:     { bsonType: "string" },
        user_agent:     { bsonType: "string" },
        // status has ONE enum value today.
        status:         { enum: ["SUCCESS"] },
        duration_ms:    { bsonType: "int", minimum: 0 },
        login_method:     { bsonType: "string" },
        statement_period: { bsonType: "string" },
        bulk:             { bsonType: "bool" }
      },
      oneOf: [
        {
          properties: {
            activity_type: { enum: ["LOGIN"] },
            login_method:  { enum: ["PASSWORD","OTP"] }
          },
          required: ["login_method"]
        },
        {
          properties: {
            activity_type:        { enum: ["STATEMENT_VIEW"] },
            statement_period:     { bsonType: "string" }
          },
          required: ["statement_period"]
        }
      ]
    }
  },
  validationLevel: "strict",
  validationAction: "error"
});

// Helpful read indexes for both collections.
db.member_documents.createIndex({ rsa_number: 1, uploaded_at: -1 });
db.member_documents.createIndex({ document_type: 1, status: 1 });
db.portal_activity.createIndex({ rsa_number: 1, occurred_at: -1 });
db.portal_activity.createIndex({ activity_type: 1, occurred_at: -1 });

print("01_setup.js: collections member_documents and portal_activity created with $jsonSchema validators.");
