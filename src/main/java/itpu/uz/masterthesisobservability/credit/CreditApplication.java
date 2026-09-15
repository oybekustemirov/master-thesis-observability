package itpu.uz.masterthesisobservability.credit;

import jakarta.persistence.*;
import lombok.Getter;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.math.BigDecimal;
import java.time.Instant;

/**
 * A credit application moving through the bank's stages.
 *
 * <p>The current stage is a plain String checked against {@code CREDIT_STAGE} rather than an
 * enum. Stages are configuration in this design — a bank whose process differs replaces rows in
 * a table — and an enum would move that decision into a recompile.
 */
@Entity
@Table(name = "CREDIT_APPLICATION")
@Getter
public class CreditApplication {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "APP_ID")
    private Long appId;

    @Column(name = "APP_REF", nullable = false, unique = true)
    private String appRef;

    @Column(name = "CUSTOMER_REF", nullable = false)
    private String customerRef;

    @Column(name = "PRODUCT", nullable = false)
    private String product;

    @Column(name = "AMOUNT", nullable = false)
    private BigDecimal amount;

    @Column(name = "CURRENCY", nullable = false)
    private String currency;

    @Column(name = "CHANNEL", nullable = false)
    private String channel;

    @Column(name = "BRANCH_CODE", nullable = false)
    private String branchCode;

    @Column(name = "CURRENT_STAGE", nullable = false)
    private String currentStage;

    @Column(name = "OUTCOME")
    private String outcome;

    // TIMESTAMP, not TIMESTAMP_UTC. Hibernate maps Instant to TIMESTAMP WITH TIME ZONE by
    // default, and Oracle then raises ORA-18716 on every read of a plain TIMESTAMP(6) column.
    @JdbcTypeCode(SqlTypes.TIMESTAMP)
    @Column(name = "SUBMITTED_AT", nullable = false)
    private Instant submittedAt;

    @JdbcTypeCode(SqlTypes.TIMESTAMP)
    @Column(name = "CLOSED_AT")
    private Instant closedAt;

    @Column(name = "HAS_COLLATERAL", nullable = false)
    private int hasCollateral;

    protected CreditApplication() { }

    public static CreditApplication submit(String appRef, String customerRef, String product,
                                           BigDecimal amount, String currency, String channel,
                                           String branchCode, boolean collateral) {
        var a = new CreditApplication();
        a.appRef = appRef;
        a.customerRef = customerRef;
        a.product = product;
        a.amount = amount;
        a.currency = currency == null ? "UZS" : currency;
        a.channel = channel;
        a.branchCode = branchCode;
        a.currentStage = "ARIZA_KIRITISH";
        a.submittedAt = Instant.now();
        a.hasCollateral = collateral ? 1 : 0;
        return a;
    }

    /** Terminal stages close the case; everything else just moves it along. */
    void moveTo(String stage, boolean terminal) {
        this.currentStage = stage;
        if (terminal) {
            this.outcome = stage;
            this.closedAt = Instant.now();
        }
    }
}
