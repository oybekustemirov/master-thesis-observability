package itpu.uz.masterthesisobservability.service;

import itpu.uz.masterthesisobservability.api.A1TransactionView;
import itpu.uz.masterthesisobservability.api.InitiateA1Request;
import itpu.uz.masterthesisobservability.domain.*;
import itpu.uz.masterthesisobservability.outbox.EmitsEvent;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * The A1 workflow under measurement. This class is IDENTICAL in every observability mode —
 * only the emission strategy behind {@code @EmitsEvent} changes. Keeping the business path
 * byte-for-byte constant is what makes the measured deltas attributable to the instrumentation
 * rather than to incidental differences between implementations.
 */
@Service
@RequiredArgsConstructor
public class A1TransactionService {

    private final TxnA1Repository transactions;
    private final LedgerEntryRepository ledger;

    @Transactional
    @EmitsEvent(type = "A1TransactionInitiated", aggregateId = "#result.txnId()")
    public A1TransactionView initiate(InitiateA1Request request) {
        var txn = TxnA1.initiate(request.txnRef(), request.debitAccount(),
                request.creditAccount(), request.amount(), request.currency(), request.channel());
        return A1TransactionView.of(transactions.save(txn));
    }

    @Transactional
    @EmitsEvent(type = "A1TransactionValidated", aggregateId = "#result.txnId()")
    public A1TransactionView validate(String txnRef) {
        var txn = load(txnRef);
        txn.validate();
        return A1TransactionView.of(txn);
    }

    /**
     * Two tables in one transaction. This is what makes multi-table grouping a real problem
     * for CDC (which sees two independent row changes and must rejoin them through the
     * transaction-metadata topic) and a non-problem for the wrapper and the hybrid (one
     * business operation produces exactly one event).
     */
    @Transactional
    @EmitsEvent(type = "A1TransactionProcessed", aggregateId = "#result.txnId()")
    public A1TransactionView process(String txnRef) {
        var txn = load(txnRef);
        txn.process();
        ledger.save(LedgerEntry.debit(txn));
        ledger.save(LedgerEntry.credit(txn));
        return A1TransactionView.of(txn);
    }

    @Transactional
    @EmitsEvent(type = "A1TransactionRejected", aggregateId = "#result.txnId()")
    public A1TransactionView reject(String txnRef, String reasonCode) {
        var txn = load(txnRef);
        txn.reject(reasonCode);
        return A1TransactionView.of(txn);
    }

    @Transactional(readOnly = true)
    public A1TransactionView find(String txnRef) {
        return A1TransactionView.of(
                transactions.findByTxnRef(txnRef).orElseThrow(() -> new TxnNotFoundException(txnRef)));
    }

    private TxnA1 load(String txnRef) {
        return transactions.findByTxnRefForUpdate(txnRef)
                .orElseThrow(() -> new TxnNotFoundException(txnRef));
    }
}
