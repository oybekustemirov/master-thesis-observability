package itpu.uz.masterthesisobservability.domain;

import jakarta.persistence.*;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.time.Instant;

/**
 * The A1 transaction aggregate. Deliberately holds counterparty account NUMBERS rather than
 * associations to ACCOUNT: a counterparty often belongs to another institution, and a foreign
 * key would add constraint validation to every insert, changing the very DML cost this
 * experiment sets out to measure.
 */
@Entity
@Table(name = "TXN_A1")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class TxnA1 {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "TXN_ID")
    private Long txnId;

    @Column(name = "TXN_REF", nullable = false, updatable = false)
    private String txnRef;

    @Column(name = "DEBIT_ACCOUNT", nullable = false, updatable = false)
    private String debitAccount;

    @Column(name = "CREDIT_ACCOUNT", nullable = false, updatable = false)
    private String creditAccount;

    @Column(name = "AMOUNT", nullable = false, updatable = false)
    private BigDecimal amount;

    @Column(name = "CURRENCY", nullable = false, updatable = false)
    private String currency;

    @Enumerated(EnumType.STRING)
    @Column(name = "STATUS", nullable = false, length = 16)
    private A1Status status;

    @Column(name = "CHANNEL")
    private String channel;

    @Column(name = "REJECT_CODE")
    private String rejectCode;

    /*
     * Hibernate maps Instant to the TIMESTAMP_UTC JDBC type, which on Oracle is
     * TIMESTAMP WITH TIME ZONE. Reading a plain TIMESTAMP(6) column through it raises
     * ORA-18716. Forcing SqlTypes.TIMESTAMP keeps Instant in the domain model (the right
     * type for an event timestamp) while matching the physical column. Combined with
     * hibernate.jdbc.time_zone=UTC, values are stored and read as UTC.
     */
    @JdbcTypeCode(SqlTypes.TIMESTAMP)
    @Column(name = "CREATED_AT", nullable = false, updatable = false)
    private Instant createdAt;

    @JdbcTypeCode(SqlTypes.TIMESTAMP)
    @Column(name = "UPDATED_AT", nullable = false)
    private Instant updatedAt;

    @Version
    @Column(name = "VERSION", nullable = false)
    private Integer version;

    public static TxnA1 initiate(String txnRef, String debitAccount, String creditAccount,
                                 BigDecimal amount, String currency, String channel) {
        var txn = new TxnA1();
        txn.txnRef        = txnRef;
        txn.debitAccount  = debitAccount;
        txn.creditAccount = creditAccount;
        txn.amount        = amount;
        txn.currency      = currency;
        txn.channel       = channel;
        txn.status        = A1Status.INITIATED;
        txn.createdAt     = Instant.now();
        txn.updatedAt     = txn.createdAt;
        return txn;
    }

    public void validate() {
        transitionTo(A1Status.VALIDATED);
    }

    public void process() {
        transitionTo(A1Status.PROCESSED);
    }

    public void reject(String reasonCode) {
        this.rejectCode = reasonCode;
        transitionTo(A1Status.REJECTED);
    }

    private void transitionTo(A1Status next) {
        if (!status.canTransitionTo(next)) {
            throw new IllegalA1TransitionException(txnRef, status, next);
        }
        this.status = next;
        this.updatedAt = Instant.now();
    }
}
