package itpu.uz.masterthesisobservability.domain;

import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;

import java.util.Optional;

public interface TxnA1Repository extends JpaRepository<TxnA1, Long> {

    Optional<TxnA1> findByTxnRef(String txnRef);

    /**
     * Pessimistic lock on the state transition. A1 transitions are short and contended only
     * by retries, so SELECT FOR UPDATE is cheaper here than an optimistic-lock retry loop —
     * and it keeps the measured DML pattern stable across modes, which matters more.
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select t from TxnA1 t where t.txnRef = :txnRef")
    Optional<TxnA1> findByTxnRefForUpdate(String txnRef);
}
