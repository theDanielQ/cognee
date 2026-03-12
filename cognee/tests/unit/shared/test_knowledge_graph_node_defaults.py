from cognee.shared.data_models import Node


def test_node_missing_name_and_description_are_filled_from_id():
    node = Node.model_validate({"id": "cognee", "type": "Software"})

    assert node.name == "cognee"
    assert node.description == "cognee"


def test_node_missing_description_uses_name():
    node = Node.model_validate({"id": "cognee", "type": "Software", "name": "Cognee"})

    assert node.name == "Cognee"
    assert node.description == "Cognee"
