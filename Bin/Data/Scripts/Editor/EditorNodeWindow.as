// Urho3D editor attribute inspector window handling
#include "Scripts/Editor/AttributeEditor.as"

Window@ attributeInspectorWindow;
UIElement@ parentContainer;
XMLFile@ nodeXMLResource;
XMLFile@ componentXMLResource;

bool applyMaterialList = true;
bool attributesDirty = false;
bool attributesFullDirty = false;

const String STRIKED_OUT = "——";   // Two unicode EM DASH (U+2014)
const ShortStringHash NODE_IDS_VAR("NodeIDs");
const ShortStringHash COMPONENT_IDS_VAR("ComponentIDs");
const ShortStringHash UI_ELEMENT_IDS_VAR("UIElementIDs");

uint nodeContainerIndex = M_MAX_UNSIGNED;
uint componentContainerStartIndex = 0;
uint elementContainerIndex = M_MAX_UNSIGNED;

void DeleteAllContainers()
{
    parentContainer.RemoveAllChildren();
    nodeContainerIndex = M_MAX_UNSIGNED;
    componentContainerStartIndex = 0;
    elementContainerIndex = M_MAX_UNSIGNED;
}

UIElement@ GetContainer(uint index)
{
    return parentContainer.children[index];
}

UIElement@ GetNodeContainer()
{
    if (nodeContainerIndex != M_MAX_UNSIGNED)
        return GetContainer(nodeContainerIndex);

    nodeContainerIndex = parentContainer.numChildren;
    parentContainer.LoadXML(nodeXMLResource, uiStyle);
    UIElement@ container = GetContainer(nodeContainerIndex);
    SubscribeToEvent(container.GetChild("NewVarDropDown", true), "ItemSelected", "CreateNodeVariable");
    SubscribeToEvent(container.GetChild("DeleteVarButton", true), "Released", "DeleteNodeVariable");
    ++componentContainerStartIndex;
    return container;
}

UIElement@ GetComponentContainer(uint index)
{
    for (uint i = parentContainer.numChildren - componentContainerStartIndex; i <= index; ++i)
        parentContainer.LoadXML(componentXMLResource, uiStyle);
    return parentContainer.children[componentContainerStartIndex + index];
}

UIElement@ GetElementContainer()
{
    if (elementContainerIndex != M_MAX_UNSIGNED)
        return GetContainer(elementContainerIndex);

    elementContainerIndex = parentContainer.numChildren;
    parentContainer.LoadXML(nodeXMLResource, uiStyle);
    UIElement@ container = GetContainer(elementContainerIndex);
    SubscribeToEvent(container.GetChild("NewVarDropDown", true), "ItemSelected", "CreateUIElementVariable");
    SubscribeToEvent(container.GetChild("DeleteVarButton", true), "Released", "DeleteUIElementVariable");
    return container;
}

void CreateAttributeInspectorWindow()
{
    if (attributeInspectorWindow !is null)
        return;

    InitResourcePicker();
    InitVectorStructs();

    attributeInspectorWindow = ui.LoadLayout(cache.GetResource("XMLFile", "UI/EditorNodeWindow.xml"));
    nodeXMLResource = cache.GetResource("XMLFile", "UI/EditorNode.xml");
    componentXMLResource = cache.GetResource("XMLFile", "UI/EditorComponent.xml");
    parentContainer = attributeInspectorWindow.GetChild("ParentContainer");
    ui.root.AddChild(attributeInspectorWindow);
    int height = Min(ui.root.height - 60, 500);
    attributeInspectorWindow.SetSize(300, height);
    attributeInspectorWindow.SetPosition(ui.root.width - 20 - attributeInspectorWindow.width, 40);
    attributeInspectorWindow.opacity = uiMaxOpacity;
    attributeInspectorWindow.BringToFront();

    SubscribeToEvent(attributeInspectorWindow.GetChild("CloseButton", true), "Released", "HideAttributeInspectorWindow");
    SubscribeToEvent(attributeInspectorWindow, "LayoutUpdated", "HandleWindowLayoutUpdated");
}

void HideAttributeInspectorWindow()
{
    attributeInspectorWindow.visible = false;
}

bool ShowAttributeInspectorWindow()
{
    attributeInspectorWindow.visible = true;
    attributeInspectorWindow.BringToFront();
    return true;
}

void HandleWindowLayoutUpdated()
{
    for (uint i = 0; i < parentContainer.numChildren; ++i)
    {
        ListView@ list = GetContainer(i).GetChild("AttributeList");
        if (list is null)
            continue;

        // At the moment, only 'Is Enabled' container (place-holder + check box) is being created as child of the list view instead of as list item
        // When window resize and so the list's width is changed, adjust the 'Is enabled' container width so that check box stays at the right most position
        int width = list.width;
        for (uint i = 0; i < list.numChildren; ++i)
        {
            UIElement@ element = list.children[i];
            if (!element.internal)
                element.SetFixedWidth(width);
        }
    }
}

Array<Serializable@> ToSerializableArray(Array<Node@> nodes)
{
    Array<Serializable@> serializables;
    for (uint i = 0; i < nodes.length; ++i)
        serializables.Push(nodes[i]);
    return serializables;
}

void UpdateAttributeInspector(bool fullUpdate = true)
{
    attributesDirty = false;
    if (fullUpdate)
        attributesFullDirty = false;

    // If full update delete all containers and added them back as necessary
    if (fullUpdate)
        DeleteAllContainers();

    if (!editNodes.empty)
    {
        UIElement@ container = GetNodeContainer();

        Text@ nodeTitle = container.GetChild("TitleText");
        String nodeType;

        if (editNode !is null)
        {
            String idStr;
            if (editNode.id >= FIRST_LOCAL_ID)
                idStr = " (Local ID " + String(editNode.id - FIRST_LOCAL_ID) + ")";
            else
                idStr = " (ID " + String(editNode.id) + ")";
            nodeType = editNode.typeName;
            nodeTitle.text = nodeType + idStr;
        }
        else
        {
            nodeType = editNodes[0].typeName;
            nodeTitle.text = nodeType + " (ID " + STRIKED_OUT + " : " + editNodes.length + "x)";
        }
        IconizeUIElement(nodeTitle, nodeType);

        ListView@ list = container.GetChild("AttributeList");
        UpdateAttributes(ToSerializableArray(editNodes), list, fullUpdate);

        if (fullUpdate)
        {
            //\TODO Avoid hardcoding
            // Resize the node editor according to the number of variables, up to a certain maximum
            uint maxAttrs = Clamp(list.contentElement.numChildren, MIN_NODE_ATTRIBUTES, MAX_NODE_ATTRIBUTES);
            list.SetFixedHeight(maxAttrs * ATTR_HEIGHT + 2);
            container.SetFixedHeight(maxAttrs * ATTR_HEIGHT + 60);
        }
    }

    if (!editComponents.empty)
    {
        uint numEditableComponents = editComponents.length / numEditableComponentsPerNode;
        String multiplierText;
        if (numEditableComponents > 1)
            multiplierText = " (" + numEditableComponents + "x)";

        for (uint j = 0; j < numEditableComponentsPerNode; ++j)
        {
            Text@ componentTitle = GetComponentContainer(j).GetChild("TitleText");
            componentTitle.text = GetComponentTitle(editComponents[j * numEditableComponents]) + multiplierText;
            IconizeUIElement(componentTitle, editComponents[j * numEditableComponents].typeName);
            SetIconEnabledColor(componentTitle, editComponents[j * numEditableComponents].enabledEffective);

            Array<Serializable@> components;
            for (uint i = 0; i < numEditableComponents; ++i)
                components.Push(editComponents[j * numEditableComponents + i]);

            UpdateAttributes(components, GetComponentContainer(j).GetChild("AttributeList"), fullUpdate);
        }
    }

    if (!editUIElements.empty)
    {
        UIElement@ container = GetElementContainer();

        Text@ titleText = container.GetChild("TitleText");
        String elementType;

        if (editUIElement !is null)
        {
            elementType = editUIElement.typeName;
            titleText.text = elementType + " [ID " + GetUIElementID(editUIElement).ToString() + "]";
        }
        else
        {
            elementType = editUIElements[0].typeName;

            bool sameType = true;
            for (uint i = 1; i < editUIElements.length; ++i)
            {
                if (editUIElements[i].typeName != elementType)
                {
                    sameType = false;
                    break;
                }
            }
            titleText.text = (sameType ? elementType : "Mixed type") + " [ID " + STRIKED_OUT + " : " + editUIElements.length + "x]";
            if (!sameType)
                elementType = "";   // No icon
        }
        IconizeUIElement(titleText, elementType);

        UpdateAttributes(editUIElements, container.GetChild("AttributeList"), fullUpdate);
    }

    if (parentContainer.numChildren > 0)
        UpdateAttributeInspectorIcons();
    else
    {
        // No editables, insert a dummy component container to show the information
        Text@ titleText = GetComponentContainer(0).GetChild("TitleText");
        titleText.text = "Select editable objects";
    }
}

void UpdateNodeAttributes()
{
    UpdateAttributes(ToSerializableArray(editNodes), GetNodeContainer().GetChild("AttributeList"), false);
}

void UpdateAttributeInspectorIcons()
{
    if (!editNodes.empty)
    {
        Text@ nodeTitle = GetNodeContainer().GetChild("TitleText");
        if (editNode !is null)
            SetIconEnabledColor(nodeTitle, editNode.enabled);
        else if (editNodes.length > 0)
        {
            bool hasSameEnabledState = true;

            for (uint i = 1; i < editNodes.length; ++i)
            {
                if (editNodes[i].enabled != editNodes[0].enabled)
                {
                    hasSameEnabledState = false;
                    break;
                }
            }

            SetIconEnabledColor(nodeTitle, editNodes[0].enabled, !hasSameEnabledState);
        }
    }

    if (!editComponents.empty)
    {
        uint numEditableComponents = editComponents.length / numEditableComponentsPerNode;

        for (uint j = 0; j < numEditableComponentsPerNode; ++j)
        {
            Text@ componentTitle = GetComponentContainer(j).GetChild("TitleText");

            bool enabledEffective = editComponents[j * numEditableComponents].enabledEffective;
            bool hasSameEnabledState = true;
            for (uint i = 1; i < numEditableComponents; ++i)
            {
                if (editComponents[j * numEditableComponents + i].enabledEffective != enabledEffective)
                {
                    hasSameEnabledState = false;
                    break;
                }
            }

            SetIconEnabledColor(componentTitle, enabledEffective, !hasSameEnabledState);
        }
    }
}

void PostEditAttribute(Array<Serializable@>@ serializables, uint index, const Array<Variant>& oldValues)
{
    // Create undo actions for the edits
    EditActionGroup group;
    for (uint i = 0; i < serializables.length; ++i)
    {
        EditAttributeAction action;
        action.Define(serializables[i], index, oldValues[i]);
        group.actions.Push(action);
    }

    SaveEditActionGroup(group);

    // If a UI-element changing its 'Is Modal' attribute, clear the hierarchy list selection
    bool saveModalElement = false;
    if (serializables[0].attributeInfos[index].name == "Is Modal")
    {
        hierarchyList.ClearSelection();
        saveModalElement = true;
    }

    for (uint i = 0; i < serializables.length; ++i)
    {
        PostEditAttribute(serializables[i], index);

        // Need to save a reference of the modal element being tested as otherwise there is no way to get it back when it is being dismissed by ESC key
        if (saveModalElement)
            modalUIElements.Push(serializables[i]);
    }
}

void PostEditAttribute(Serializable@ serializable, uint index)
{
    // If a StaticModel/AnimatedModel/Skybox model was changed, apply a possibly different material list
    if (applyMaterialList && serializable.attributeInfos[index].name == "Model")
    {
        StaticModel@ staticModel = cast<StaticModel>(serializable);
        if (staticModel !is null)
            ApplyMaterialList(staticModel);
    }
}

void SetAttributeEditorID(UIElement@ attrEdit, Array<Serializable@>@ serializables)
{
    // All target serializables must be either nodes, ui-elements, or components
    Array<Variant> ids;
    switch (GetType(serializables[0]))
    {
    case ITEM_NODE:
        for (uint i = 0; i < serializables.length; ++i)
            ids.Push(cast<Node>(serializables[i]).id);
        attrEdit.vars[NODE_IDS_VAR] = ids;
        break;

    case ITEM_COMPONENT:
        for (uint i = 0; i < serializables.length; ++i)
            ids.Push(cast<Component>(serializables[i]).id);
        attrEdit.vars[COMPONENT_IDS_VAR] = ids;
        break;

    case ITEM_UI_ELEMENT:
        for (uint i = 0; i < serializables.length; ++i)
            ids.Push(GetUIElementID(cast<UIElement>(serializables[i])));
        attrEdit.vars[UI_ELEMENT_IDS_VAR] = ids;
        break;

    default:
        break;
    }
}

Array<Serializable@>@ GetAttributeEditorTargets(UIElement@ attrEdit)
{
    Array<Serializable@> ret;
    Variant variant = attrEdit.GetVar(NODE_IDS_VAR);
    if (!variant.empty)
    {
        Array<Variant>@ ids = variant.GetVariantVector();
        for (uint i = 0; i < ids.length; ++i)
        {
            Node@ node = editorScene.GetNode(ids[i].GetUInt());
            if (node !is null)
                ret.Push(node);
        }
    }
    else
    {
        variant = attrEdit.GetVar(COMPONENT_IDS_VAR);
        if (!variant.empty)
        {
            Array<Variant>@ ids = variant.GetVariantVector();
            for (uint i = 0; i < ids.length; ++i)
            {
                Component@ component = editorScene.GetComponent(ids[i].GetUInt());
                if (component !is null)
                    ret.Push(component);
            }
        }
        else
        {
            variant = attrEdit.GetVar(UI_ELEMENT_IDS_VAR);
            if (!variant.empty)
            {
                Array<Variant>@ ids = variant.GetVariantVector();
                for (uint i = 0; i < ids.length; ++i)
                {
                    UIElement@ element = editorUIElement.GetChild(UI_ELEMENT_ID_VAR, ids[i], true);
                    if (element !is null)
                        ret.Push(element);
                }
            }
        }
    }

    return ret;
}

void CreateNodeVariable(StringHash eventType, VariantMap& eventData)
{
    if (editNodes.length == 0)
        return;

    String newKey;
    Variant newValue;
    CreateNewVariable(eventData, newKey, newValue);
    if (newKey.empty)
        return;

    // If we overwrite an existing variable, must recreate the attribute-editor(s) for the correct type
    bool overwrite = false;
    for (uint i = 0; i < editNodes.length; ++i)
    {
        overwrite = overwrite || editNodes[i].vars.Contains(newKey);
        editNodes[i].vars[newKey] = newValue;
    }
    if (overwrite)
        attributesFullDirty = true;
    else
        attributesDirty = true;
}

void DeleteNodeVariable(StringHash eventType, VariantMap& eventData)
{
    if (editNodes.length == 0)
        return;

    String delKey;
    DeleteVariable(eventData, delKey);
    if (delKey.empty)
        return;

    bool erased = false;
    for (uint i = 0; i < editNodes.length; ++i)
    {
        // \todo Should first check whether var in question is editable
        erased = editNodes[i].vars.Erase(delKey) || erased;
    }
    if (erased)
        attributesDirty = true;
}

void CreateUIElementVariable(StringHash eventType, VariantMap& eventData)
{
    if (editUIElements.length == 0)
        return;

    String newKey;
    Variant newValue;
    CreateNewVariable(eventData, newKey, newValue);
    if (newKey.empty)
        return;

    // If we overwrite an existing variable, must recreate the attribute-editor(s) for the correct type
    bool overwrite = false;
    for (uint i = 0; i < editUIElements.length; ++i)
    {
        UIElement@ element = cast<UIElement>(editUIElements[i]);
        overwrite = overwrite || element.vars.Contains(newKey);
        element.vars[newKey] = newValue;
    }
    if (overwrite)
        attributesFullDirty = true;
    else
        attributesDirty = true;
}

void DeleteUIElementVariable(StringHash eventType, VariantMap& eventData)
{
    if (editUIElements.length == 0)
        return;

    String delKey;
    DeleteVariable(eventData, delKey);
    if (delKey.empty)
        return;

    bool erased = false;
    for (uint i = 0; i < editUIElements.length; ++i)
    {
        // \todo Should first check whether var in question is editable
        erased = cast<UIElement>(editUIElements[i]).vars.Erase(delKey) || erased;
    }
    if (erased)
        attributesDirty = true;
}

void CreateNewVariable(VariantMap& eventData, String& newKey, Variant& newValue)
{
    DropDownList@ dropDown = eventData["Element"].GetUIElement();
    LineEdit@ nameEdit = dropDown.parent.GetChild("VarNameEdit");
    newKey = nameEdit.text.Trimmed().Replaced(";", "");
    if (newKey.empty)
        return;

    editorScene.RegisterVar(newKey);

    switch (dropDown.selection)
    {
    case 0:
        newValue = int(0);
        break;
    case 1:
        newValue = false;
        break;
    case 2:
        newValue = float(0.0);
        break;
    case 3:
        newValue = String();
        break;
    case 4:
        newValue = Vector3();
        break;
    case 5:
        newValue = Color();
        break;
    }
}

void DeleteVariable(VariantMap& eventData, String& delKey)
{
    Button@ button = eventData["Element"].GetUIElement();
    LineEdit@ nameEdit = button.parent.GetChild("VarNameEdit", true);
    delKey = nameEdit.text.Trimmed().Replaced(";", "");

    // Do not actually unregister the variable name as the same variable name may still be used by other attribute list
}
