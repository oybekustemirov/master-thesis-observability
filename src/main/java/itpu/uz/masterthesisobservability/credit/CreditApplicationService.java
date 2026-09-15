package itpu.uz.masterthesisobservability.credit;

import itpu.uz.masterthesisobservability.outbox.EmitsEvent;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.Set;

/**
 * The credit workflow, instrumented through exactly the same mechanism as the A1 transaction
 * workflow.
 *
 * <p>This is the join between the two halves of the thesis. Chapters 5 and 6 measure which
 * capture mechanism delivers every state change and what each costs; this class produces the
 * state changes that Chapter 7 analyses. It carries no emission logic of its own — the active
 * mode behind {@code @EmitsEvent} decides whether the event goes to an outbox row, an AQ
 * message, or nowhere at all because Debezium will read the row change from the redo log.
 */
@Service
@RequiredArgsConstructor
public class CreditApplicationService {

    /** Stages that close a case. Held here rather than in the table because whether a stage is
        terminal is a property of the workflow's shape, not a tunable parameter. */
    private static final Set<String> TERMINAL =
            Set.of("AJRATISH", "RAD_ETILDI", "BEKOR_QILINDI");

    private final CreditApplicationRepository applications;
    private final CreditStageEventWriter events;

    @Transactional
    @EmitsEvent(type = "CreditApplicationSubmitted",
                aggregateType = "credit.application",
                aggregateId = "#result.appRef()")
    public CreditStageEventView submit(String appRef, String customerRef, String product,
                                       BigDecimal amount, String currency, String channel,
                                       String branchCode, boolean collateral, String actorId) {
        var app = applications.save(CreditApplication.submit(
                appRef, customerRef, product, amount, currency, channel, branchCode, collateral));
        var now = Instant.now();
        var stage = events.stage("ARIZA_KIRITISH");
        events.record(app.getAppId(), null, "ARIZA_KIRITISH", now, now, now,
                actorId, "KREDIT_MUTAXASSISI", branchCode, false);
        return CreditStageEventView.of(app, null, "ARIZA_KIRITISH", stage,
                now, now, now, actorId, "KREDIT_MUTAXASSISI", false, false);
    }

    /**
     * Advances an application to the next stage and records the interval it spent in it.
     *
     * <p>{@code enteredAt} is supplied by the caller rather than taken as "now", because the
     * case entered the stage when the previous transition completed — often days earlier. Taking
     * it as now would make every stage appear instantaneous and delete the entire subject of the
     * analysis.
     */
    @Transactional
    @EmitsEvent(type = "CreditApplicationStageChanged",
                aggregateType = "credit.application",
                aggregateId = "#result.appRef()")
    public CreditStageEventView advance(String appRef, String toStage, Instant enteredAt,
                                        Instant pickedUpAt, Instant completedAt,
                                        String actorId, String actorRole, boolean rework) {
        var app = applications.findByAppRefForUpdate(appRef)
                .orElseThrow(() -> new CreditApplicationNotFoundException(appRef));
        var stage = events.stage(toStage);          // raises if the stage is not defined
        var from = app.getCurrentStage();
        // completedAt is accepted rather than assumed to be "now" for the same reason enteredAt
        // is: the first thing a bank does with this is backfill from its existing system, where
        // every stage completed in the past. Forcing "now" would collapse every historical case
        // into a single instant and make the whole log unusable.
        var completed = completedAt == null ? Instant.now() : completedAt;
        var entered = enteredAt == null ? completed : enteredAt;
        boolean terminal = TERMINAL.contains(toStage);

        events.record(app.getAppId(), from, toStage, entered, pickedUpAt, completed,
                actorId, actorRole, app.getBranchCode(), rework);
        app.moveTo(toStage, terminal);

        return CreditStageEventView.of(app, from, toStage, stage,
                entered, pickedUpAt, completed, actorId, actorRole, rework, terminal);
    }

    @Transactional(readOnly = true)
    public CreditApplication find(String appRef) {
        return applications.findByAppRef(appRef)
                .orElseThrow(() -> new CreditApplicationNotFoundException(appRef));
    }
}
