-- =============================================================================
-- Schema: lending
-- Description: Operational schema for a fintech lending platform. Models the
--              full loan lifecycle: products, borrowers, origination,
--              amortization schedules, payment tracking, and collections.
--
-- Tables:
--   lending.products             Catalogue of lending products
--   lending.borrowers            Master borrower registry (individuals + SMEs)
--   lending.individual_borrowers Individual-specific attributes
--   lending.company_borrowers    Company-specific attributes
--   lending.loans                Loan contracts and lifecycle status
--   lending.payment_schedule     Amortization schedule with payment tracking
--   lending.payments             Payment transactions
--   lending.collections          Collection activities for delinquent loans
--
-- Notes:
--   - All timestamps use TIMESTAMPTZ (stored in UTC)
--   - updated_at columns are maintained automatically via trigger
--   - payments references payment_schedule via composite FK
--     (loan_id, installment_number) to enforce referential consistency
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS lending;

CREATE OR REPLACE FUNCTION lending.update_timestamp_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';


CREATE TABLE IF NOT EXISTS lending.products (
    product_id              INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY, 
    name                    TEXT            NOT NULL UNIQUE, 
    min_amount              NUMERIC(15,2)   NOT NULL CHECK (min_amount > 0),
    max_amount              NUMERIC(15,2)   NOT NULL CHECK (max_amount > 0),
    interest_rate_annual    NUMERIC(6,4)    NOT NULL CHECK (interest_rate_annual >= 0 AND interest_rate_annual <= 1),
    term_months             INTEGER         NOT NULL CHECK (term_months > 0),
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    CHECK (min_amount <= max_amount)
);

COMMENT ON TABLE lending.products IS 
'Catalogue of lending products offered to customers, defining loan constraints and pricing conditions.';

COMMENT ON COLUMN lending.products.product_id IS 
'Unique identifier of the lending product. Generated automatically.';

COMMENT ON COLUMN lending.products.name IS 
'Human-readable name of the lending product (e.g., Personal Loan, Auto Loan).';

COMMENT ON COLUMN lending.products.min_amount IS 
'Minimum loan amount allowed for this product in the smallest currency unit.';

COMMENT ON COLUMN lending.products.max_amount IS 
'Maximum loan amount allowed for this product in the smallest currency unit.';

COMMENT ON COLUMN lending.products.interest_rate_annual IS 
'Annual nominal interest rate applied to the loan, expressed as a decimal where 0.25 represents 25%.';

COMMENT ON COLUMN lending.products.term_months IS 
'Loan term length expressed in months.';

COMMENT ON COLUMN lending.products.created_at IS 
'Timestamp when the product record was created (stored in UTC).';

COMMENT ON COLUMN lending.products.updated_at IS 
'Timestamp when the product record was last updated (automatically maintained, stored in UTC).';

DROP TRIGGER IF EXISTS trg_products_update_modtime ON lending.products;
CREATE TRIGGER trg_products_update_modtime
BEFORE UPDATE ON lending.products
FOR EACH ROW
WHEN (OLD IS DISTINCT FROM NEW)
EXECUTE FUNCTION lending.update_timestamp_column();


DO $$
BEGIN
    CREATE TYPE lending.borrowers_segment AS ENUM ('individual', 'sme');
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS lending.borrowers (
    borrower_id  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tax_id       TEXT                       NOT NULL,
    tax_country  TEXT                       NOT NULL DEFAULT 'MX' CHECK (char_length(tax_country) = 2),
    credit_score INTEGER                    NOT NULL CHECK (credit_score BETWEEN 300 AND 850),
    segment      lending.borrowers_segment  NOT NULL,
    is_active    BOOLEAN                    NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ                NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ                NOT NULL DEFAULT now(),
    UNIQUE (tax_country, tax_id)
);

COMMENT ON TABLE lending.borrowers IS 
'Master table of borrowers. Stores common attributes for both individuals and companies, including identification, segmentation, and lifecycle status.';

COMMENT ON COLUMN lending.borrowers.borrower_id IS 
'Unique identifier of the borrower. Generated automatically.';

COMMENT ON COLUMN lending.borrowers.tax_id IS 
'Tax identification number of the borrower (e.g., RFC in Mexico). Unique within each country.';

COMMENT ON COLUMN lending.borrowers.tax_country IS 
'ISO country code where the tax_id is issued (e.g., MX for Mexico).';

COMMENT ON COLUMN lending.borrowers.credit_score IS 

'Credit score of the borrower based on external or internal evaluation (typically between 300 and 850).';

COMMENT ON COLUMN lending.borrowers.segment IS 
'Type of borrower: individual (natural person) or sme (small/medium enterprise).';

COMMENT ON COLUMN lending.borrowers.is_active IS 
'Indicates whether the borrower is active and eligible for lending operations.';

COMMENT ON COLUMN lending.borrowers.created_at IS 
'Timestamp when the borrower record was created (stored in UTC).';

COMMENT ON COLUMN lending.borrowers.updated_at IS 
'Timestamp when the borrower record was last updated (automatically maintained, stored in UTC).';

DROP TRIGGER IF EXISTS trg_borrowers_update_modtime ON lending.borrowers;
CREATE TRIGGER trg_borrowers_update_modtime
BEFORE UPDATE ON lending.borrowers
FOR EACH ROW
WHEN (OLD IS DISTINCT FROM NEW)
EXECUTE FUNCTION lending.update_timestamp_column();


CREATE TABLE IF NOT EXISTS lending.individual_borrowers (
    borrower_id INTEGER PRIMARY KEY 
        REFERENCES lending.borrowers(borrower_id) ON DELETE CASCADE,
    first_name  TEXT NOT NULL,
    last_name   TEXT NOT NULL,
    birth_date  DATE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE lending.individual_borrowers IS 
'Additional attributes specific to individual borrowers (natural persons). Extends the base borrowers table.';

COMMENT ON COLUMN lending.individual_borrowers.borrower_id IS 
'Primary key and foreign key referencing lending.borrowers. Identifies the individual borrower.';

COMMENT ON COLUMN lending.individual_borrowers.first_name IS 
'First name of the individual borrower.';

COMMENT ON COLUMN lending.individual_borrowers.last_name IS 
'Last name of the individual borrower.';

COMMENT ON COLUMN lending.individual_borrowers.birth_date IS 
'Date of birth of the individual borrower.';

COMMENT ON COLUMN lending.individual_borrowers.created_at IS 
'Timestamp when the individual borrower record was created (stored in UTC).';

COMMENT ON COLUMN lending.individual_borrowers.updated_at IS 
'Timestamp when the individual borrower record was last updated (automatically maintained, stored in UTC).';

DROP TRIGGER IF EXISTS trg_individual_borrowers_update_modtime ON lending.individual_borrowers;
CREATE TRIGGER trg_individual_borrowers_update_modtime
BEFORE UPDATE ON lending.individual_borrowers
FOR EACH ROW
WHEN (OLD IS DISTINCT FROM NEW)
EXECUTE FUNCTION lending.update_timestamp_column();


CREATE TABLE IF NOT EXISTS lending.company_borrowers (
    borrower_id     INTEGER PRIMARY KEY
        REFERENCES lending.borrowers(borrower_id) ON DELETE CASCADE,
    legal_name      TEXT NOT NULL,
    trade_name      TEXT,
    created_at      TIMESTAMPTZ             NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ             NOT NULL DEFAULT now()
);

COMMENT ON TABLE lending.company_borrowers IS 
'Additional attributes specific to company borrowers (legal entities). Extends the base borrowers table.';

COMMENT ON COLUMN lending.company_borrowers.borrower_id IS 
'Primary key and foreign key referencing lending.borrowers. Identifies the company borrower.';

COMMENT ON COLUMN lending.company_borrowers.legal_name IS 
'Registered legal name of the company.';

COMMENT ON COLUMN lending.company_borrowers.trade_name IS 
'Commercial or trade name of the company, if different from the legal name.';

COMMENT ON COLUMN lending.company_borrowers.created_at IS 
'Timestamp when the company borrower record was created (stored in UTC).';

COMMENT ON COLUMN lending.company_borrowers.updated_at IS 
'Timestamp when the company borrower record was last updated (automatically maintained, stored in UTC).';

DROP TRIGGER IF EXISTS trg_company_borrowers_update_modtime ON lending.company_borrowers;
CREATE TRIGGER trg_company_borrowers_update_modtime
BEFORE UPDATE ON lending.company_borrowers
FOR EACH ROW
WHEN (OLD IS DISTINCT FROM NEW)
EXECUTE FUNCTION lending.update_timestamp_column();


DO $$
BEGIN
    CREATE TYPE lending.loans_status AS ENUM ('active', 'paid_off', 'defaulted', 'charged_off');
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS lending.loans (
    loan_id           INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    borrower_id       INTEGER NOT NULL REFERENCES lending.borrowers(borrower_id),
    product_id        INTEGER NOT NULL REFERENCES lending.products(product_id),
    disbursement_date DATE NOT NULL,
    amount            NUMERIC(15,2) NOT NULL CHECK (amount > 0),
    interest_rate     NUMERIC(6,4) NOT NULL CHECK (interest_rate >= 0 AND interest_rate <= 1),
    term_months       INTEGER NOT NULL CHECK (term_months > 0),
    status            lending.loans_status NOT NULL DEFAULT 'active',
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE lending.loans IS 
'Represents individual loan contracts issued to borrowers under a specific product, including financial terms, lifecycle status, and key dates.';

COMMENT ON COLUMN lending.loans.loan_id IS 
'Unique identifier of the loan. Generated automatically.';

COMMENT ON COLUMN lending.loans.borrower_id IS 
'Reference to the borrower who receives the loan. Links to lending.borrowers.';

COMMENT ON COLUMN lending.loans.product_id IS 
'Reference to the lending product that defines the loan conditions. Links to lending.products.';

COMMENT ON COLUMN lending.loans.disbursement_date IS 
'Date when the loan amount was disbursed to the borrower.';

COMMENT ON COLUMN lending.loans.amount IS 
'Principal loan amount disbursed to the borrower, expressed in the smallest currency unit.';

COMMENT ON COLUMN lending.loans.interest_rate IS 
'Annual nominal interest rate applied to the loan, expressed as a decimal where 0.25 represents 25%.';

COMMENT ON COLUMN lending.loans.term_months IS 
'Total duration of the loan in months.';

COMMENT ON COLUMN lending.loans.status IS 
'Current lifecycle status of the loan: active, paid_off, defaulted, or charged_off.';

COMMENT ON COLUMN lending.loans.created_at IS 
'Timestamp when the loan record was created (stored in UTC).';

COMMENT ON COLUMN lending.loans.updated_at IS 
'Timestamp when the loan record was last updated (automatically maintained, stored in UTC).';

DROP TRIGGER IF EXISTS trg_loans_update_modtime ON lending.loans;
CREATE TRIGGER trg_loans_update_modtime
BEFORE UPDATE ON lending.loans
FOR EACH ROW
WHEN (OLD IS DISTINCT FROM NEW)
EXECUTE FUNCTION lending.update_timestamp_column();


DO $$
BEGIN
    CREATE TYPE lending.payment_status AS ENUM ('pending', 'partial', 'paid', 'late');
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;


CREATE TABLE IF NOT EXISTS lending.payment_schedule (
    schedule_id         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY, 
    loan_id             INTEGER NOT NULL 
        REFERENCES lending.loans(loan_id) ON DELETE CASCADE,
    installment_number  INTEGER NOT NULL CHECK (installment_number > 0), 
    due_date            DATE NOT NULL,
    principal_due       NUMERIC(15,2) NOT NULL CHECK (principal_due > 0),
    interest_due        NUMERIC(15,2) NOT NULL CHECK (interest_due >= 0),
    total_due           NUMERIC(15,2) NOT NULL CHECK (total_due > 0),
    amount_paid         NUMERIC(15,2) NOT NULL DEFAULT 0 CHECK (amount_paid >= 0),
    status              lending.payment_status NOT NULL DEFAULT 'pending',
    paid_at             TIMESTAMPTZ,
    last_payment_at     TIMESTAMPTZ,
    days_past_due       INTEGER NOT NULL DEFAULT 0 CHECK (days_past_due >= 0),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE (loan_id, installment_number),
    CHECK (total_due = principal_due + interest_due)
);

COMMENT ON TABLE lending.payment_schedule IS 
'Represents the amortization schedule of a loan, tracking each installment, its expected amounts, payment progress, and delinquency status over time.';

COMMENT ON COLUMN lending.payment_schedule.schedule_id IS 
'Unique identifier of the payment schedule entry. Generated automatically.';

COMMENT ON COLUMN lending.payment_schedule.loan_id IS 
'Reference to the loan associated with this installment. Links to lending.loans.';

COMMENT ON COLUMN lending.payment_schedule.installment_number IS 
'Sequential number of the installment within the loan term (starting from 1).';

COMMENT ON COLUMN lending.payment_schedule.due_date IS 
'Date when the installment payment is due. Used to determine delinquency.';

COMMENT ON COLUMN lending.payment_schedule.principal_due IS 
'Portion of the installment corresponding to principal repayment.';

COMMENT ON COLUMN lending.payment_schedule.interest_due IS 
'Portion of the installment corresponding to interest charges.';

COMMENT ON COLUMN lending.payment_schedule.total_due IS 
'Total amount due for the installment (principal_due + interest_due).';

COMMENT ON COLUMN lending.payment_schedule.amount_paid IS 
'Total amount paid by the borrower toward this installment, accumulated from payment transactions.';

COMMENT ON COLUMN lending.payment_schedule.status IS 
'Current status of the installment: pending, partial, paid, or late.';

COMMENT ON COLUMN lending.payment_schedule.paid_at IS 
'Timestamp when the installment was fully paid (i.e., amount_paid >= total_due).';

COMMENT ON COLUMN lending.payment_schedule.last_payment_at IS 
'Timestamp of the most recent payment applied to this installment.';

COMMENT ON COLUMN lending.payment_schedule.days_past_due IS 
'Number of days the installment is overdue relative to due_date (0 if not overdue or already paid).';

COMMENT ON COLUMN lending.payment_schedule.created_at IS 
'Timestamp when the schedule record was created (stored in UTC).';

COMMENT ON COLUMN lending.payment_schedule.updated_at IS 
'Timestamp when the schedule record was last updated (automatically maintained, stored in UTC).';

DROP TRIGGER IF EXISTS trg_payment_schedule_update_modtime ON lending.payment_schedule;
CREATE TRIGGER trg_payment_schedule_update_modtime
BEFORE UPDATE ON lending.payment_schedule
FOR EACH ROW
WHEN (OLD IS DISTINCT FROM NEW)
EXECUTE FUNCTION lending.update_timestamp_column();



CREATE TABLE IF NOT EXISTS lending.payments (
    payment_id         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    loan_id            INTEGER NOT NULL,
    installment_number INTEGER NOT NULL,
    amount_paid        NUMERIC(15,2) NOT NULL CHECK (amount_paid > 0),
    payment_date       TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

    FOREIGN KEY (loan_id, installment_number)
        REFERENCES lending.payment_schedule(loan_id, installment_number)
        ON DELETE CASCADE
);

COMMENT ON TABLE lending.payments IS 
'Records actual payment transactions made by borrowers, representing cash inflows applied to specific loan installments.';

COMMENT ON COLUMN lending.payments.loan_id IS 
'Loan identifier enforced via composite foreign key with installment_number. 
References lending.payment_schedule(loan_id, installment_number).';

COMMENT ON COLUMN lending.payments.payment_id IS 
'Unique identifier of the payment transaction. Generated automatically.';

COMMENT ON COLUMN lending.payments.installment_number IS 
'Sequential number of the installment being paid. Links to lending.payment_schedule.';

COMMENT ON COLUMN lending.payments.amount_paid IS 
'Amount of money paid in this transaction.';

COMMENT ON COLUMN lending.payments.payment_date IS 
'Timestamp when the payment was made.';

COMMENT ON COLUMN lending.payments.created_at IS 
'Timestamp when the payment record was created (stored in UTC).';

COMMENT ON COLUMN lending.payments.updated_at IS 
'Timestamp when the payment record was last updated (automatically maintained, stored in UTC).';

DROP TRIGGER IF EXISTS trg_payments_update_modtime ON lending.payments;
CREATE TRIGGER trg_payments_update_modtime
BEFORE UPDATE ON lending.payments
FOR EACH ROW
WHEN (OLD IS DISTINCT FROM NEW)
EXECUTE FUNCTION lending.update_timestamp_column();

DO $$
BEGIN
    CREATE TYPE lending.collections_action_taken AS ENUM ('call', 'sms', 'email', 'legal_notice', 'restructuring');
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
    CREATE TYPE lending.collections_dpd_bucket AS ENUM ('0-30', '31-60', '61-90', '91-120', '120+');
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS lending.collections (
    collection_id       INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY, 
    loan_id             INTEGER NOT NULL 
        REFERENCES lending.loans(loan_id) ON DELETE CASCADE,
    dpd_bucket          lending.collections_dpd_bucket NOT NULL,
    outstanding_balance NUMERIC(15,2) NOT NULL CHECK (outstanding_balance >= 0),
    action_taken        lending.collections_action_taken NOT NULL,
    agent_id            INTEGER,
    action_date         TIMESTAMPTZ NOT NULL DEFAULT now(),
    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE lending.collections IS 
'Tracks collection activities and borrower interactions for delinquent loans, including delinquency buckets, outstanding balances, and actions taken by collection agents.';

COMMENT ON COLUMN lending.collections.collection_id IS 
'Unique identifier of the collection record. Generated automatically.';

COMMENT ON COLUMN lending.collections.loan_id IS 
'Reference to the loan under collection management. Links to lending.loans.';

COMMENT ON COLUMN lending.collections.dpd_bucket IS 
'Delinquency bucket based on days past due (DPD), representing how overdue the loan is (e.g., 0-30, 31-60 days).';

COMMENT ON COLUMN lending.collections.outstanding_balance IS 
'Remaining unpaid balance of the loan at the time of the collection action.';

COMMENT ON COLUMN lending.collections.action_taken IS 
'Type of the collection action performed (e.g., call, SMS, email, legal notice, restructuring).';

COMMENT ON COLUMN lending.collections.agent_id IS 
'Identifier of the collection agent or system that performed the action.';

COMMENT ON COLUMN lending.collections.action_date IS 
'Timestamp when the collection action was executed. Defaults to current time.';

COMMENT ON COLUMN lending.collections.notes IS 
'Additional notes or details about the interaction with the borrower or outcome of the collection action.';

COMMENT ON COLUMN lending.collections.created_at IS 
'Timestamp when the collection record was created (stored in UTC).';

COMMENT ON COLUMN lending.collections.updated_at IS 
'Timestamp when the collection record was last updated (automatically maintained, stored in UTC).';

DROP TRIGGER IF EXISTS trg_collections_update_modtime ON lending.collections;
CREATE TRIGGER trg_collections_update_modtime
BEFORE UPDATE ON lending.collections
FOR EACH ROW
WHEN (OLD IS DISTINCT FROM NEW)
EXECUTE FUNCTION lending.update_timestamp_column();

