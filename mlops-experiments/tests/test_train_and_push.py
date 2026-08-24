from experiments.train_and_push import RunResult, select_best


def test_select_best_prefers_accuracy() -> None:
    candidates = [
        RunResult("a", 0.1, 100, 0.90, 0.20),
        RunResult("b", 1.0, 200, 0.95, 0.30),
    ]
    assert select_best(candidates).run_id == "b"


def test_select_best_uses_loss_as_tiebreaker() -> None:
    candidates = [
        RunResult("a", 0.1, 100, 0.95, 0.20),
        RunResult("b", 1.0, 200, 0.95, 0.10),
    ]
    assert select_best(candidates).run_id == "b"

