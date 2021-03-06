package com.abstratt.kirra.mdd.rest.impl.v1.representation;

import java.io.IOException;
import java.io.Reader;
import java.io.StringWriter;
import java.net.URI;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Map.Entry;
import java.util.StringTokenizer;

import org.codehaus.jackson.JsonFactory;
import org.codehaus.jackson.JsonGenerator;
import org.codehaus.jackson.JsonNode;
import org.codehaus.jackson.JsonParseException;
import org.codehaus.jackson.JsonParser;
import org.codehaus.jackson.JsonProcessingException;
import org.codehaus.jackson.map.ObjectMapper;
import org.codehaus.jackson.map.SerializationConfig;
import org.codehaus.jackson.node.ArrayNode;
import org.codehaus.jackson.node.ObjectNode;

import com.abstratt.kirra.DataScope;
import com.abstratt.kirra.Entity;
import com.abstratt.kirra.Helper;
import com.abstratt.kirra.Instance;
import com.abstratt.kirra.KirraException;
import com.abstratt.kirra.Property;
import com.abstratt.kirra.Relationship;
import com.abstratt.kirra.Relationship.Style;
import com.abstratt.kirra.SchemaManagement;
import com.abstratt.kirra.Tuple;
import com.abstratt.kirra.TupleType;
import com.abstratt.kirra.TypeRef;

public class TupleParser {
    
    private SchemaManagement schemaManagement;
    
    public TupleParser(SchemaManagement schemaManagement) {
        this.schemaManagement = schemaManagement;
    }

    public Object convertSlotValue(TypeRef expectedType, JsonNode slotValueNode) {
        Object fieldValue = null;
        if (slotValueNode == null) {
            fieldValue = null;
        } else if (slotValueNode.isIntegralNumber()) {
            fieldValue = slotValueNode.asLong();
        } else if (slotValueNode.isNumber()) {
            fieldValue = slotValueNode.asDouble();
        } else if (slotValueNode.isBoolean()) {
            fieldValue = slotValueNode.asBoolean();
        } else if (slotValueNode.isTextual()) {
            fieldValue = slotValueNode.asText();
        } else if (slotValueNode.isNull()) {
            fieldValue = null;
        } else if (slotValueNode.isArray()) {
            ArrayList<Object> array = new ArrayList<Object>();
            ArrayNode asArray = (ArrayNode) slotValueNode;
            for (JsonNode jsonNode : asArray) {
                array.add(convertSlotValue(expectedType, jsonNode));
            }
            fieldValue = array;
        } else if (slotValueNode.isObject()) {
            TupleType expectedTupleType = schemaManagement.getTupleType(expectedType);
            Map<String, Object> map = new LinkedHashMap<String, Object>();
            ObjectNode asObject = (ObjectNode) slotValueNode;
            for (Iterator<Map.Entry<String, JsonNode>> entries = asObject.getFields(); entries.hasNext(); ) {
                Entry<String, JsonNode> entry = entries.next();
                Property entryProperty = expectedTupleType.getProperty(entry.getKey());
                if (entryProperty != null)
                    map.put(entry.getKey(), convertSlotValue(entryProperty.getTypeRef(), entry.getValue()));
            }
            Tuple tuple = new Tuple(expectedTupleType.getTypeRef());
            tuple.setValues(map);
            fieldValue = tuple;
        }
        return fieldValue;
    }

    public Tuple getTupleFromJsonRepresentation(JsonNode tupleRepresentation, TupleType tupleType) {
        Tuple newTuple = new Tuple(tupleType.getTypeRef());
        if (tupleRepresentation == null || tupleRepresentation.isNull())
            return null;
        Iterator<String> fieldNames = tupleRepresentation.getFieldNames();
        while (fieldNames.hasNext()) {
            String fieldName = fieldNames.next();
            JsonNode fieldValueNode = tupleRepresentation.get(fieldName);
            Property property = tupleType.getProperty(fieldName);
            if (property != null)
                setProperty(newTuple, fieldName, fieldValueNode);
        }
        return newTuple;
    }

    public List<?> getValuesFromJsonRepresentation(JsonNode representation, TypeRef type,
            boolean multiple) {
        if (representation == null)
            return null;
        ArrayNode asArray = multiple ? (ArrayNode) representation : null;
        switch (type.getKind()) {
        case Tuple:
        case Entity:
            TupleType tupleType = schemaManagement.getTupleType(type);
            return multiple ? getTuplesFromJsonRepresentation(asArray, tupleType) : Arrays.asList(getTupleFromJsonRepresentation(representation, tupleType));
        case Primitive:
        case Enumeration:
            return multiple ? TupleParser.getPrimitiveValuesFromJsonRepresentation(asArray) : Arrays.asList(TupleParser
                    .getPrimitiveValueFromJsonRepresentation(representation));
        default:
            throw new KirraException("Unexpected result type", null, KirraException.Kind.SCHEMA);
        }

    }

    public static <T extends JsonNode> T parse(Reader contents) throws IOException, JsonParseException, JsonProcessingException {
        JsonParser parser = TupleParser.jsonFactory.createJsonParser(contents);
        return (T) parser.readValueAsTree();
    }

    public static String renderAsJson(Object toRender) {
        try {
            StringWriter writer = new StringWriter();
            ((ObjectMapper) TupleParser.jsonFactory.getCodec()).defaultPrettyPrintingWriter().writeValue(writer, toRender);
            return writer.toString();
        } catch (IOException e) {
            throw new RuntimeException(e);
        }
    }

    public Instance resolveLink(JsonNode fieldValueNode, TypeRef type) {
        if (fieldValueNode == null || fieldValueNode.isNull())
            return null;
        return resolveLink(fieldValueNode.getTextValue(), type);
    }

    public Instance resolveLink(String uriString, TypeRef type) {
        if (uriString == null || uriString.trim().isEmpty())
            return null;
        String objectId = null;
        StringTokenizer stringTokenizer = new StringTokenizer(URI.create(uriString).getPath(), "/");
        while (stringTokenizer.hasMoreTokens())
            objectId = stringTokenizer.nextToken();
        if (objectId == null)
            return null;
        Instance toLink = new Instance(type, objectId);
        return toLink;
    }

    public void updateInstanceFromJsonRepresentation(JsonNode toUpdate, Entity entity, Instance existingInstance) {
        JsonNode values = toUpdate.get("values");
        if (values == null || values.isNull())
            return;
        Iterator<String> fieldNames = values.getFieldNames();
        while (fieldNames.hasNext()) {
            String fieldName = fieldNames.next();
            JsonNode fieldValueNode = values.get(fieldName);
            Property property = entity.getProperty(fieldName);
            if (property != null) {
                if (property.isEditable())
                    setProperty(existingInstance, fieldName, fieldValueNode);
            } else {
                Relationship relationship = entity.getRelationship(fieldName);
                if (relationship != null)
                    if (relationship.getStyle() != Style.PARENT && relationship.isEditable())
                        updateRelationship(entity, existingInstance, relationship, fieldValueNode);
            }
        }
    }

    public void updateRelationship(Entity entity, Instance existingInstance, Relationship relationship, JsonNode fieldValueNode) {
        if (fieldValueNode == null || fieldValueNode.isNull())
            return;
        if (fieldValueNode.isTextual())
            existingInstance.setSingleRelated(relationship.getName(), resolveLink(fieldValueNode, relationship.getTypeRef()));
        else if (fieldValueNode.isArray()) {
            List<Instance> allRelated = new ArrayList<Instance>();
            for (Iterator<JsonNode> elements = ((ArrayNode) fieldValueNode).getElements(); elements.hasNext();)
                allRelated.add(resolveLink(elements.next(), relationship.getTypeRef()));
            existingInstance.setRelated(relationship.getName(), allRelated);
        } else if (fieldValueNode.isObject()) {
            existingInstance.setSingleRelated(relationship.getName(),
                    resolveLink(fieldValueNode.get("uri"), relationship.getTypeRef()));
        }
    }

    protected void setProperty(Tuple record, String fieldName, JsonNode fieldValueNode) {
        DataScope dataScope = Helper.resolveDataScope(schemaManagement, record.getTypeRef());
        Property property = dataScope.getProperty(fieldName);
        if (property != null)
            record.setValue(fieldName, convertSlotValue(property.getTypeRef(), fieldValueNode));
    }

    private static Object getPrimitiveValueFromJsonRepresentation(JsonNode jsonNode) {
        Object value = null;
        if (jsonNode.isNumber())
            value = jsonNode.getNumberValue();
        else if (jsonNode.isBoolean())
            value = jsonNode.getBooleanValue();
        else if (jsonNode.isTextual())
            value = jsonNode.getTextValue();
        return value;
    }

    private static List<?> getPrimitiveValuesFromJsonRepresentation(ArrayNode asArray) {
        List values = new ArrayList();
        for (JsonNode jsonNode : asArray)
            values.add(getPrimitiveValueFromJsonRepresentation(jsonNode));
        return values;
    }

    private List<?> getTuplesFromJsonRepresentation(ArrayNode asArray, TupleType tupleType) {
        List values = new ArrayList();
        for (JsonNode jsonNode : asArray)
            values.add(getTupleFromJsonRepresentation(jsonNode, tupleType));
        return values;
    }

    private static JsonFactory jsonFactory = new JsonFactory();

    static {
        TupleParser.jsonFactory.configure(JsonParser.Feature.ALLOW_UNQUOTED_FIELD_NAMES, true);
        TupleParser.jsonFactory.configure(JsonParser.Feature.ALLOW_SINGLE_QUOTES, true);
        TupleParser.jsonFactory.configure(JsonParser.Feature.ALLOW_COMMENTS, true);
        TupleParser.jsonFactory.configure(JsonParser.Feature.CANONICALIZE_FIELD_NAMES, true);
        ObjectMapper objectMapper = new ObjectMapper();
        objectMapper.enable(SerializationConfig.Feature.INDENT_OUTPUT);
        objectMapper.configure(JsonGenerator.Feature.QUOTE_FIELD_NAMES, true);
        objectMapper.setDateFormat(new SimpleDateFormat("yyyy/MM/dd"));
        TupleParser.jsonFactory.setCodec(objectMapper);
    }
}
