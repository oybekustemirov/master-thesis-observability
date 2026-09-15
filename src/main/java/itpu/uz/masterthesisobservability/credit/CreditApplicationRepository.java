package itpu.uz.masterthesisobservability.credit;

import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;

import java.util.Optional;

public interface CreditApplicationRepository extends JpaRepository<CreditApplication, Long> {

    Optional<CreditApplication> findByAppRef(String appRef);

    /** Row lock while a stage transition is recorded, so two officers cannot advance the same
        application concurrently and produce two conflicting event rows. */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select a from CreditApplication a where a.appRef = :ref")
    Optional<CreditApplication> findByAppRefForUpdate(String ref);
}
