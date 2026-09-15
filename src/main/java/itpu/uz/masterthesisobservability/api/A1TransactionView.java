package itpu.uz.masterthesisobservability.api;

import itpu.uz.masterthesisobservability.domain.A1Status;
import itpu.uz.masterthesisobservability.domain.TxnA1;

import java.math.BigDecimal;
import java.time.Instant;

public record A1TransactionView(Long txnId, String txnRef, String debitAccount,
                                String creditAccount, BigDecimal amount, String currency,
                                A1Status status, String channel, String rejectCode,
                                Instant updatedAt) {

    public static A1TransactionView of(TxnA1 t) {
        return new A1TransactionView(t.getTxnId(), t.getTxnRef(), t.getDebitAccount(),
                t.getCreditAccount(), t.getAmount(), t.getCurrency(), t.getStatus(),
                t.getChannel(), t.getRejectCode(), t.getUpdatedAt());
    }
}
