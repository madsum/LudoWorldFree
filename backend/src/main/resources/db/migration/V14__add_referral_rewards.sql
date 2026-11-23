CREATE TABLE referral_codes (
    code varchar(16) PRIMARY KEY,
    referrer_player_id uuid NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE referral_attributions (
    referred_player_id uuid PRIMARY KEY,
    referrer_player_id uuid NOT NULL,
    referral_code varchar(16) NOT NULL REFERENCES referral_codes(code),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT referral_attributions_not_self CHECK (referred_player_id <> referrer_player_id)
);

CREATE INDEX referral_attributions_referrer_idx
    ON referral_attributions(referrer_player_id);

ALTER TABLE gold_transactions DROP CONSTRAINT IF EXISTS gold_transactions_transaction_type_check;
ALTER TABLE gold_transactions ADD CONSTRAINT gold_transactions_transaction_type_check
    CHECK (transaction_type IN (
        'AD_REWARD', 'DAILY_BONUS', 'GAME_REWARD', 'BONUS', 'PURCHASE',
        'SPEND', 'ADMIN_ADJUSTMENT', 'REFUND', 'REFERRAL_BONUS'
    ));
