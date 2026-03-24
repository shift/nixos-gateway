{ reviewers, requireApproval, approvalThreshold }:

let
  inherit (import <nixpkgs> {}) stdenv lib;

in stdenv.mkDerivation {
  name = "simulator-signoff-db";

  src = ./.;

  buildInputs = with import <nixpkgs> {}; [
    sqlite
    bash
  ];

  installPhase = ''
    mkdir -p $out/bin
    cat > $out/bin/signoff-db << 'EOF'
    #!/bin/bash
    set -euo pipefail

    DB_FILE="/var/lib/simulator/signoffs/signoffs.db"
    REVIEWERS='${builtins.toJSON reviewers}'
    REQUIRE_APPROVAL=${lib.boolToString requireApproval}
    APPROVAL_THRESHOLD=${toString approvalThreshold}

    # Initialize database
    init_db() {
        sqlite3 "$DB_FILE" << SQL
        CREATE TABLE IF NOT EXISTS signoffs (
            id TEXT PRIMARY KEY,
            reviewer_name TEXT NOT NULL,
            reviewer_email TEXT,
            reviewer_role TEXT,
            features TEXT,
            checklist_status TEXT,
            evidence_files TEXT,
            notes TEXT,
            submitted_at TEXT NOT NULL,
            approved BOOLEAN DEFAULT 0,
            approved_at TEXT,
            approved_by TEXT
        );

        CREATE TABLE IF NOT EXISTS approvals (
            id INTEGER PRIMARY KEY,
            signoff_id TEXT NOT NULL,
            approver_name TEXT NOT NULL,
            approver_email TEXT,
            approved_at TEXT NOT NULL,
            comments TEXT,
            FOREIGN KEY (signoff_id) REFERENCES signoffs(id)
        );
        SQL
    }

    # Add signoff
    add_signoff() {
        local signoff_data="$1"
        local id reviewer_name reviewer_email features notes

        id=$(echo "$signoff_data" | jq -r '.id')
        reviewer_name=$(echo "$signoff_data" | jq -r '.reviewer')
        reviewer_email=$(echo "$signoff_data" | jq -r '.reviewer_email // ""')
        features=$(echo "$signoff_data" | jq -r '.features | join(",")')
        notes=$(echo "$signoff_data" | jq -r '.notes // ""')

        sqlite3 "$DB_FILE" << SQL
        INSERT OR REPLACE INTO signoffs
        (id, reviewer_name, reviewer_email, features, notes, submitted_at)
        VALUES ('$id', '$reviewer_name', '$reviewer_email', '$features', '$notes', datetime('now'));
        SQL

        echo "Signoff recorded: $id"
    }

    # Add approval
    add_approval() {
        local signoff_id="$1"
        local approver_name="$2"
        local comments="$3"

        sqlite3 "$DB_FILE" << SQL
        INSERT INTO approvals (signoff_id, approver_name, approved_at, comments)
        VALUES ('$signoff_id', '$approver_name', datetime('now'), '$comments');
        SQL

        # Check if approval threshold is met
        local approval_count
        approval_count=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM approvals WHERE signoff_id = '$signoff_id';")

        if [[ "$approval_count" -ge "$APPROVAL_THRESHOLD" ]]; then
            sqlite3 "$DB_FILE" << SQL
            UPDATE signoffs SET approved = 1, approved_at = datetime('now')
            WHERE id = '$signoff_id';
            SQL
            echo "Signoff approved: $signoff_id"
        fi
    }

    # Get signoff status
    get_signoff_status() {
        local signoff_id="$1"
        sqlite3 "$DB_FILE" -json << SQL
        SELECT s.*, json_group_array(
            json_object('approver_name', a.approver_name, 'approved_at', a.approved_at, 'comments', a.comments)
        ) as approvals
        FROM signoffs s
        LEFT JOIN approvals a ON s.id = a.signoff_id
        WHERE s.id = '$signoff_id'
        GROUP BY s.id;
        SQL
    }

    # List all signoffs
    list_signoffs() {
        sqlite3 "$DB_FILE" -json << SQL
        SELECT s.*, json_group_array(
            json_object('approver_name', a.approver_name, 'approved_at', a.approved_at)
        ) as approvals
        FROM signoffs s
        LEFT JOIN approvals a ON s.id = a.signoff_id
        GROUP BY s.id
        ORDER BY s.submitted_at DESC;
        SQL
    }

    # Main execution
    echo "Simulator Signoff Database starting..."
    echo "Database: $DB_FILE"
    echo "Require Approval: $REQUIRE_APPROVAL"
    echo "Approval Threshold: $APPROVAL_THRESHOLD"

    # Initialize database
    init_db

    echo "Signoff database initialized and ready"

    # Keep running (in real implementation, this would be a proper service)
    while true; do
        sleep 60
    done
    EOF

    chmod +x $out/bin/signoff-db
  '';
}