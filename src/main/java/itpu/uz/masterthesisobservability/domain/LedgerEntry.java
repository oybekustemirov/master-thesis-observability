package itpu.uz.masterthesisobservability.domain;

import jakarta.persistence.*;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.time.Instant;

/** Double-entry posting. Two rows per PROCESSED transaction, in the same local transaction. */
@Entity
@Table(name = "LEDGER_ENTRY")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class LedgerEntry {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "ENTRY_ID")
    private Long entryId;

    @Column(name = "TXN_ID", nullable = false)
    private Long txnId;

    @Column(name = "ACCOUNT_NO", nullable = false)
    private String accountNo;

    @Column(name = "DIRECTION", nullable = false, length = 1)
    private String direction;

    @Column(name = "AMOUNT", nullable = false)
    private BigDecimal amount;

    /*
     * Hibernate maps Instant to the TIMESTAMP_UTC JDBC type, which on Oracle is
     * TIMESTAMP WITH TIME ZONE. Reading a plain TIMESTAMP(6) column through it raises
     * ORA-18716. Forcing SqlTypes.TIMESTAMP keeps Instant in the domain model (the right
     * type for an event timestamp) while matching the physical column. Combined with
     * hibernate.jdbc.time_zone=UTC, values are stored and read as UTC.
     */
    @JdbcTypeCode(SqlTypes.TIMESTAMP)
    @Column(name = "POSTED_AT", nullable = false)
    private Instant postedAt;

    public static LedgerEntry debit(TxnA1 txn) {
        return of(txn.getTxnId(), txn.getDebitAccount(), "D", txn.getAmount());
    }

    public static LedgerEntry credit(TxnA1 txn) {
        return of(txn.getTxnId(), txn.getCreditAccount(), "C", txn.getAmount());
    }

    private static LedgerEntry of(Long txnId, String account, String direction, BigDecimal amount) {
        var e = new LedgerEntry();
        e.txnId = txnId;
        e.accountNo = account;
        e.direction = direction;
        e.amount = amount;
        e.postedAt = Instant.now();
        return e;
    }
}
