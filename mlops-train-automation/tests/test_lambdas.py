import importlib.util
from pathlib import Path
import unittest


LAMBDA_DIR = Path(__file__).parents[1] / "terraform" / "lambda"


def load_module(name: str):
    spec = importlib.util.spec_from_file_location(name, LAMBDA_DIR / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class LambdaContractTests(unittest.TestCase):
    def test_successful_workflow_contract(self):
        validate = load_module("validate")
        log_metrics = load_module("log_metrics")

        validated = validate.lambda_handler(
            {"source": "unittest", "commit": "abc123"}, None
        )
        result = log_metrics.lambda_handler(validated, None)

        self.assertEqual(validated["validation_status"], "PASSED")
        self.assertEqual(result["pipeline_status"], "SUCCEEDED")
        self.assertEqual(result["commit"], "abc123")
        self.assertEqual(result["metrics"]["validation_errors"], 0)

    def test_validation_rejects_missing_commit(self):
        validate = load_module("validate")
        with self.assertRaisesRegex(ValueError, "commit"):
            validate.lambda_handler({"source": "unittest"}, None)


if __name__ == "__main__":
    unittest.main()
