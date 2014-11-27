package com.abstratt.mdd.target.mean

import com.abstratt.kirra.TypeRef
import com.abstratt.kirra.mdd.schema.KirraMDDSchemaBuilder
import com.abstratt.mdd.core.IRepository
import java.util.List
import org.eclipse.uml2.uml.Activity
import org.eclipse.uml2.uml.AddStructuralFeatureValueAction
import org.eclipse.uml2.uml.AddVariableValueAction
import org.eclipse.uml2.uml.AnyReceiveEvent
import org.eclipse.uml2.uml.CallEvent
import org.eclipse.uml2.uml.CallOperationAction
import org.eclipse.uml2.uml.Class
import org.eclipse.uml2.uml.Classifier
import org.eclipse.uml2.uml.Constraint
import org.eclipse.uml2.uml.CreateObjectAction
import org.eclipse.uml2.uml.Event
import org.eclipse.uml2.uml.InputPin
import org.eclipse.uml2.uml.LiteralNull
import org.eclipse.uml2.uml.LiteralString
import org.eclipse.uml2.uml.Operation
import org.eclipse.uml2.uml.Property
import org.eclipse.uml2.uml.ReadExtentAction
import org.eclipse.uml2.uml.ReadLinkAction
import org.eclipse.uml2.uml.ReadSelfAction
import org.eclipse.uml2.uml.ReadStructuralFeatureAction
import org.eclipse.uml2.uml.ReadVariableAction
import org.eclipse.uml2.uml.SignalEvent
import org.eclipse.uml2.uml.State
import org.eclipse.uml2.uml.StateMachine
import org.eclipse.uml2.uml.StructuredActivityNode
import org.eclipse.uml2.uml.TestIdentityAction
import org.eclipse.uml2.uml.TimeEvent
import org.eclipse.uml2.uml.Transition
import org.eclipse.uml2.uml.Trigger
import org.eclipse.uml2.uml.ValueSpecification
import org.eclipse.uml2.uml.ValueSpecificationAction
import org.eclipse.uml2.uml.Vertex
import org.eclipse.uml2.uml.VisibilityKind

import static com.abstratt.mdd.target.mean.Utils.*

import static extension com.abstratt.kirra.mdd.core.KirraHelper.*
import static extension com.abstratt.mdd.core.util.ActivityUtils.*
import static extension com.abstratt.mdd.core.util.MDDExtensionUtils.*
import static extension com.abstratt.mdd.core.util.StateMachineUtils.*
import com.abstratt.mdd.target.mean.ActivityContext.Stage
import org.eclipse.uml2.uml.Action

class ModelGenerator extends AsyncJSGenerator {

    protected IRepository repository
    
    protected String applicationName

    protected Iterable<Class> entities
    
    new(IRepository repository) {
        this.repository = repository
        val appPackages = repository.getTopLevelPackages(null).applicationPackages
        this.applicationName = repository.getApplicationName(appPackages)
        this.entities = appPackages.entities.filter[topLevel]
    }
    
    def generateIndex() {
        '''
        require('./db.js');
        «entities.toList.topologicalSort.map[ 
            '''require('./«name».js');''' 
        ].join('\n')» 
        '''
    }
    
    def generateDb() {
        '''
        var mongoose = require('mongoose');
        var dbURI = 'mongodb://localhost/test';
        mongoose.set('debug', function (coll, method, query, doc) {
            console.log(">>>>>>>>>>");
            console.log("Collection: " + coll);
            console.log("Method: " + method);
            console.log("Query: " + JSON.stringify(query));
            console.log("Doc: " + JSON.stringify(doc));
            console.log("<<<<<<<<<");
        });
        mongoose.connect(dbURI);
        mongoose.connection.on('error', function (err) { console.log(err); } );
        mongoose.connection.on('connected', function () {
            console.log('Mongoose default connection open to ' + dbURI);
        });
        var exports = module.exports = mongoose;
        '''
    }
    
    override generateActivityRootAction(Activity activity) {
        super.generateActivityRootAction(activity)
    }
    

    def generateEntity(Class entity) {
        val otherEntities = entities.toList.topologicalSort.filter[it != entity]
        val modelName = entity.name
        '''
            var Q = require("q");
            var mongoose = require('./db.js');    
            var Schema = mongoose.Schema;
            var cls = require('continuation-local-storage');
            
            «otherEntities.map[ '''var «name» = require('./«name».js');''' ].join('\n')»

            «generateSchema(entity)»
            
            // declare model on the schema
            var exports = module.exports = mongoose.model('«modelName»', «modelName.toFirstLower»Schema);
        '''
    }
    
    def generateSchema(Class entity) {
        val schemaVar = getSchemaVar(entity)
        val queryOperations = entity.queries
        val actionOperations = entity.actions
        val attributes = entity.properties.filter[!derived]
        val attributeInvariants = attributes.map[findInvariantConstraints].flatten
        val derivedAttributes = entity.properties.filter[derived]
        val derivedRelationships = entity.entityRelationships.filter[derived]
        val privateOperations = entity.allOperations.filter[visibility == VisibilityKind.PRIVATE_LITERAL]
        val hasState = !entity.findStateProperties.empty
        
        '''
            «entity.generateComment»
            // declare schema
            var «schemaVar» = new Schema(«generateSchemaCore(entity, attributes).toString.trim»);
            «schemaVar».set('toObject', { getters: true });
            
            «IF !attributeInvariants.empty»
            /*************************** INVARIANTS ***************************/
            
            «generateAttributeInvariants(attributeInvariants)»
            «ENDIF»
            
            «IF !actionOperations.empty»
            /*************************** ACTIONS ***************************/
            
            «generateActionOperations(entity.actions)»
            «ENDIF»
            «IF !queryOperations.empty»
            /*************************** QUERIES ***************************/
            
            «generateQueryOperations(entity.queries)»
            «ENDIF»
            «IF !derivedAttributes.empty»
            /*************************** DERIVED PROPERTIES ****************/
            
            «generateDerivedAttributes(derivedAttributes)»
            «ENDIF»
            «IF !derivedRelationships.empty»
            /*************************** DERIVED RELATIONSHIPS ****************/
            
            «generateDerivedRelationships(derivedRelationships)»
            «ENDIF»
            «IF !privateOperations.empty»
            /*************************** PRIVATE OPS ***********************/
            
            «generatePrivateOperations(privateOperations)»
            «ENDIF»
            «IF hasState»
            /*************************** STATE MACHINE ********************/
            «entity.findStateProperties.map[it.type as StateMachine].head?.generateStateMachine(entity)»
            
            «ENDIF»
        '''
    }
    
    def getSchemaVar(Class entity) '''«entity.name.toFirstLower»Schema'''


    /**
     * Generates the filtering of a query based on a predicate.
     */
    def generateFilter(Activity predicate) {
        //TODO taking only first statement into account
        val statementAction = predicate.rootAction.findStatements.head
        generateFilterAction(statementAction)
    }
    
    def generateFilterValue(ValueSpecification value) {
        switch (value) {
            // the TextUML compiler maps all primitive values to LiteralString
            LiteralString : switch (value.type.name) {
                case 'String' : '''"«value.stringValue»"'''
                default : value.stringValue
            }
            LiteralNull : 'null'
            default : unsupportedElement(value)
        }
    }
    
    def dispatch CharSequence generateFilterAction(ReadStructuralFeatureAction action) {
        /* TODO: in the case the predicate is just this action (no operator), generated code is incorrect */
        val isCondition = action.result.type.name == 'Boolean'
        val property = action.structuralFeature as Property
        if (isCondition) {
            if (property.derived) {
                val derivation = property.defaultValue.resolveBehaviorReference as Activity
                derivation.generateFilter
            } else 
                '''{ '«property.name»' : true }'''
        } else '''«property.name»'''
    }
    
    def dispatch CharSequence generateFilterAction(ReadLinkAction action) {
        val fedEndData = action.endData?.head
        //'''.where('«fedEndData.end.otherEnd.name»')'''
        '''{ '«fedEndData.end.otherEnd.name»' : «generateFilterAction(fedEndData.value.sourceAction)»  }'''
    }
    
    def dispatch CharSequence generateFilterAction(ReadVariableAction action) {
        '''«action.variable.name»'''
    }
    
    def dispatch CharSequence generateFilterAction(ReadSelfAction action) {
        '''this'''
    }
    
    def dispatch CharSequence generateFilterAction(TestIdentityAction action) {
        val isEntity = action.second.type.entity
        val left = generateFilterAction(action.first.sourceAction)
        val right = generateFilterAction(action.second.sourceAction) 
        if (true)
            '''{ «left» : «right» }'''
        else
            '''{ «left» : mongoose.Types.ObjectId(«right») }'''
    }
    
    def dispatch CharSequence generateFilterAction(ValueSpecificationAction action) {
        '''«generateFilterValue(action.value)»'''
    }
    
    def dispatch CharSequence generateFilterAction(AddVariableValueAction action) {
        if (action.variable.name == '')
            generateFilterAction(action.value.sourceAction)
        else
            unsupportedElement(action)
    }
    
    def dispatch CharSequence generateFilterAction(StructuredActivityNode action) {
        ''''''
    }
    
    def dispatch CharSequence generateFilterAction(CallOperationAction action) {
        //val CharSequence argument = if (action.arguments.empty) 'true' else generateFilterAction(action.arguments.head.sourceAction)
        //'''«generateFilterAction(action.target.sourceAction)».«action.operation.toQueryOperator»(«argument»)'''
        //'''{ «generateFilterAction(action.target.sourceAction)» : {'«action.operation.toQueryOperator»': «generateFilterAction(action.arguments.head.sourceAction)»} }'''
        '''
        {
            «action.operation.toQueryOperator» : [ 
                «generateFilterAction(action.target.sourceAction)»,
                «if (action.arguments.empty) 'true' else generateFilterAction(action.arguments.head.sourceAction)»
            ]
        }'''        
    }
    
    def generatePrivateOperations(Iterable<Operation> operations) {
        generateActionOperations(operations)
    }
    
    def generateDerivedAttributes(Iterable<Property> derivedAttributes) {
        derivedAttributes.map[generateDerivedAttribute].join('\n')
    }
    
    def generateDerivedRelationships(Iterable<Property> derivedRelationships) {
        derivedRelationships.map[generateDerivedRelationship].join('\n')
    }
    
    def generateDerivedAttribute(Property derivedAttribute) {
        val schemaVar = getSchemaVar(derivedAttribute.class_)
        val defaultValue = derivedAttribute.defaultValue
        if (defaultValue == null)
            return ''
        val derivation = defaultValue.resolveBehaviorReference as Activity
        val prefix = if (derivedAttribute.type.name == 'Boolean') 'is' else 'get'
        '''
        «IF derivedAttribute.static»
        «derivedAttribute.generateComment»«schemaVar».statics.«prefix»«derivedAttribute.name.toFirstUpper» = function () {
            «derivation.generateActivity»
        };
        «ELSE»
        «derivedAttribute.generateComment»«schemaVar».virtual('«derivedAttribute.name»').get(function () {
            «derivation.generateActivity»
        });
        «ENDIF»
        '''
    }
    
    def generateDerivedRelationship(Property derivedRelationship) {
        val schemaVar = getSchemaVar(derivedRelationship.class_)
        val defaultValue = derivedRelationship.defaultValue
        if (defaultValue == null)
            return ''
        val derivation = defaultValue.resolveBehaviorReference as Activity
        val namespace = if (derivedRelationship.static) 'statics' else 'methods' 
        '''
        «derivedRelationship.generateComment»«schemaVar».«namespace».get«derivedRelationship.name.toFirstUpper» = function () {
            «derivation.generateActivity»
        };
        '''
    }
    
    def generateActionOperations(Iterable<Operation> actions) {
        actions.map[generateActionOperation].join('\n')
    }
    
    def generateAttributeInvariants(Iterable<Constraint> invariants) {
        invariants.map[generateAttributeInvariant].join('\n')
    }
    
    def generateAttributeInvariant(Constraint invariant) {
        ''
// TODO        
//        val property = invariant.constrainedElements.head as Property
//        val schemaVar = '''«property.class_.name.toFirstLower»Schema'''
//        '''
//        «schemaVar».path('«property.name»').validate(
//            «invariant.generatePredicate.toString.trim»,
//            'validation of `{PATH}` failed with value `{VALUE}`'
//        );
//        '''
    }

    def generateActionOperation(Operation actionOperation) {
        val schemaVar = getSchemaVar(actionOperation.class_)
        val parameters = actionOperation.parameters
        val namespace = if (actionOperation.static) "statics" else "methods"
        '''
        «actionOperation.generateComment»«schemaVar».«namespace».«actionOperation.name» = function («parameters.map[name].join(', ')») «generateActionOperationBehavior(actionOperation)»;
        '''
    }
    
    def generateActionOperationBehavior(Operation action) {
        val firstMethod = action.methods?.head
        if(firstMethod == null) {
            // a method-less operation, generate default action implementation (check preconditions and SSM animation)
            application.newActivityContext(null)
            try {
                // call generatePipeline directly as there is no activity to generate stuff from
                addActionPrologue(action)
                addActionEpilogue(action)
                '''
                {
                    «generatePipeline()»
                }'''
            } finally {
                application.dropActivityContext
            } 
        } else 
            '''
            {
                «generateActivity(firstMethod as Activity)»
            }'''
    }
    
    override generateActivityPrefix(Activity activity) {
        '''
        «super.generateActivityPrefix(activity)»
        '''
    }
    
    override generateActivitySuffix(Activity activity) {
//        val specification = activity.specification
//        if (specification instanceof Operation) {
//            if (specification.action)
//                return '''«generateSelfReference».save();'''
//        }
        super.generateActivitySuffix(activity)
    }
    
    override decorateStage(Stage stage, CharSequence output) {
        if (stage.isLastInPipeline(true) && context.activity.operation != null && !context.activity.operation.query) {
            val workingSet = if (context.activity.operation.static) newLinkedHashSet() else newLinkedHashSet(generateSelfReference)
            workingSet.addAll(context.findVariables.map[it.name])
            if (workingSet.empty) '' else {
                '''
                Q.all([
                    «workingSet.map[
                    '''
                        Q().then(function() {
                            «generateSave(it, false)»
                        })'''].join(',\n')»
                ]).then(«output»)'''
            }
        } else
            output 
    }
    
    
    override addActionPrologue(Operation action) {
//        val stages = context.stages
//        action.preconditions.map[
//            generatePredicate(it)
//            stages += '''
//            function (outcome) {
//                if (!outcome) {
//                    throw "«StringUtils.trimToNull(it.comments) ?: '''Precondition violated: «it.name ?: '?'»'''»";
//                }
//            }
//            '''
//        ]
    }
    
    override addActionEpilogue(Operation action) {
//        val hasState = !action.class_.findStateProperties.empty
//        if (hasState) {
//            context.stages += generateActionCallEventTrigger(action)
//        }
//        context.stages += generateObjectSaving
    }
    
        
    def generateActionCallEventTrigger(Operation action) {
        '''
        function () {
            this.handleEvent('«action.name»')
        }'''
    }
    
    def generateObjectSaving() {
        '''
        function () {
            console.log('Saving...');
            return this.save(); 
        }'''
    }
    

    def generateQueryOperations(Iterable<Operation> queries) {
        queries.map[generateQueryOperation(it)].join('\n')
    }
    
    def generateQueryOperation(Operation queryOperation) {
        val schemaVar = getSchemaVar(queryOperation.class_)
        val parameters = queryOperation.parameters
        val namespace = if (queryOperation.static) "statics" else "methods"
        '''
            «schemaVar».«namespace».«queryOperation.name» = function («parameters.map[name].join(', ')») «generateQueryOperationBody(queryOperation)»;
        '''
    }
    
    def generateQueryOperationBody(Operation queryOperation) {
        generateActionOperationBehavior(queryOperation)
    }
    
    def dispatch CharSequence doGenerateAction(ReadExtentAction action) {
        '''«generateSelfReference».model('«action.classifier.name»').find()'''
    }
    
    def generateSave(CharSequence target, boolean returnSaved) {
        // If the saved object is to be returned, need to extract the saved object from
        // the array returned by save, where the the first element is the created/updated object.
        val optionalValueCollector = if (true || returnSaved) '''
        .then(function(saveResult) {
            «target» = saveResult[0];
        })''' else ''
        // generate the saving statement
        '''
        return «generateMongoosePromise(target, 'save', #[])»«optionalValueCollector»;
        '''
    }
    
    override CharSequence generateAddVariableValueAction(AddVariableValueAction action) {
        val actionActivity = action.actionActivity
        if (actionActivity.specification instanceof Operation) {
            val asOperation = actionActivity.specification as Operation
            if (asOperation.query)
                '''
                return «generateMongoosePromise(super.generateAction(action.value), 'exec', #[])»
                '''
            else super.generateAddVariableValueAction(action)
        } else
            super.generateAddVariableValueAction(action)
    }
    
    override def generateCreateObjectAction(CreateObjectAction action) {
        //generateMongoosePromise('''new «generateClassReference(action.classifier)»()''', 'save', #[]).toString
        '''new «generateClassReference(action.classifier)»()'''
    }

    override generateReadStructuralFeatureAction(ReadStructuralFeatureAction action) {
        val asProperty = action.structuralFeature as Property
        if (asProperty.derivedRelationship && action.object != null)
            // derived relationships are actually getter functions
            // no need to worry about statics - relationships are never static
            '''«action.object.generateAction».get«asProperty.name.toFirstUpper»()'''
        else if (action.object != null && asProperty.linkRelationship)
            generateTraverseRelationshipAction(action.object, asProperty)
        else
            super.generateReadStructuralFeatureAction(action)
    }
    
    override generateAddStructuralFeatureValueAction(AddStructuralFeatureValueAction action) {
        val asProperty = action.structuralFeature as Property
        if (action.object != null && asProperty.linkRelationship) {
            val thisEnd = asProperty
            val otherEnd = asProperty.otherEnd
            val thisEndAction = action.value
            val otherEndAction = action.object
            '''
            «generateLinkCreation(otherEndAction, thisEnd, thisEndAction, otherEnd, true)»
            «generateLinkCreation(thisEndAction, otherEnd, otherEndAction, thisEnd, false)»'''
        } else
            super.generateAddStructuralFeatureValueAction(action)        
    }

    override generateTraverseRelationshipAction(InputPin target, Property property) {
        if (property.childRelationship)
            // nested objects can be read as normal JS slots
            return generateTraverseRelationshipAction(target, property)

        if (property.multivalued)
            // one to many, search from the other (many) side
            '''«generateTraverseToMany(property, target)»'''
        else
            // one to one or many to one, search from this side
            '''«generateTraverseToOne(property, target)»'''
    }
    
    def generateMongoosePromise(CharSequence target, String operation, List<CharSequence> parameters) {
        '''Q.npost(«target», '«operation»', [ «parameters.join(', ')» ])'''
    }
    
    def generateTraverseToOne(Property property, InputPin target) {
        generateMongoosePromise(property.type.name, 'findOne', #['''({ _id : «target.sourceAction.generateAction».«property.name» })'''])
    }
    
    
    def generateTraverseToMany(Property property, InputPin target) {
        generateMongoosePromise(property.type.name, 'find', #['''({ «property.otherEnd.name» : «target.sourceAction.generateAction»._id })'''])
    }
    
    
    override CharSequence generateBasicTypeOperationCall(Classifier classifier, CallOperationAction action) {
        val operation = action.operation
        
        if (classifier != null)
            return switch (classifier.qualifiedName) {
                case 'mdd_types::System' : switch (operation.name) {
                    case 'user' : '''cls.getNamespace('currentUser')'''
                }
                default: super.generateBasicTypeOperationCall(classifier, action)
            }
        super.generateBasicTypeOperationCall(classifier, action)         
    }
    
    protected override CharSequence generateCallOperationAction(CallOperationAction action) {
        if (action.target == null || !action.target.multivalued)
            super.generateCallOperationAction(action)
        else 
            switch action.operation.name {
                case 'head' : action.target.generateAction
                case 'asSequence' : action.target.generateAction
                case 'select' : generateSelect(action)
                case 'collect' : generateCollect(action)
                case 'reduce' : generateReduce(action)
                case 'size' : generateCount(action)
                case 'forEach' : generateForEach(action)
                case 'isEmpty' : generateIsEmpty(action)
                case 'any' : generateExists(action)
                case 'includes' : generateIncludes(action)
                case 'sum' : generateAggregation(action, "sum")
                case 'max' : generateAggregation(action, "max")
                case 'min' : generateAggregation(action, "min")
                default : unsupportedElement(action, action.operation.name)
            }
    }
    
    private def generateSelect(CallOperationAction action) {
        '''«generateAction(action.target.sourceAction)».where(«generateFilter(action.arguments.head.sourceClosure)»)'''
    }
    
    private def generateCollect(CallOperationAction action) {
        '/*TBD*/collect'
    }
    
    private def generateReduce(CallOperationAction action) {
        '/*TBD*/reduce'
    }
    
    private def generateCount(CallOperationAction action) {
        '''«action.target.generateAction».length'''
    }
    
    private def generateForEach(CallOperationAction action) {
        '/*TBD*/forEach'
    }
    
    private def generateIsEmpty(CallOperationAction action) {
        '/*TBD*/isEmpty'
    }
    
    private def generateExists(CallOperationAction action) {
        '''«action.generateSelect».findOne()'''
    }
    
    private def generateIncludes(CallOperationAction action) {
        '/*TBD*/includes'
    }
    
    private def generateAggregation(CallOperationAction action, String operator) {
        val transformer = action.arguments.head.sourceClosure
        val rootAction = transformer.rootAction.findStatements.head.sourceAction 
        if (rootAction instanceof ReadStructuralFeatureAction) {
            val property = rootAction.structuralFeature 
            '''«action.target.type.name».aggregate()
              .group({ _id: null, result: { $«operator»: '$«property.name»' } })
              .select('-id result')'''
        } else
            unsupportedElement(transformer)
    }
    
    def generateAggregation(Activity reductor) {
        //TODO taking only first statement into account
        val statementAction = reductor.rootAction.findStatements.head
        if (statementAction instanceof CallOperationAction) generateAggregation(statementAction) else unsupportedElement(statementAction)
    }
    
    def generateAggregation(CallOperationAction action) {
        val aggregateOp = toAggregateOperator(action.operation)
        '''
        .group({ _id: null, result: { $«aggregateOp»: '$balance' } }).select('-id maxBalance')
        '''
    }
    
    private def toAggregateOperator(Operation operation) {
        switch (operation.name) {
            case 'sum': 'sum'
            default : unsupportedElement(operation)
        }
    }
    
    private def toQueryOperator(Operation operation) {
        switch (operation.name) {
            case 'and': '$and'
            case 'or': '$or'
            // workaround - not is mapped to ne(true)
            case 'not': '$ne'
            case 'notEquals': '$ne'
            case 'lowerThan': '$lt'
            case 'greaterThan': '$gt'
            case 'lowerOrEquals': '$lte'
            case 'greaterOrEquals': '$gte'
            case 'equals': '$eq'
            case 'same': '$eq'
            default: '''/*unknown:«operation.name»*/«operation.name»'''
        }
    }
    

    def CharSequence generateSchemaCore(Class clazz, Iterable<Property> properties) {
        val generatedAttributes = properties.map[generateSchemaAttribute(it)]
        val generatedRelationships = clazz.entityRelationships.filter[!derived && !it.parentRelationship && !it.childRelationship].map[generateSchemaRelationship(it)]
        val generatedSubschemas = clazz.entityRelationships.filter[!derived && it.childRelationship].map[generateSubSchema(it)]
        '''
        {
            «(generatedAttributes + generatedRelationships + generatedSubschemas).join(',\n')»
        }'''
    }
    
    def generateSchemaAttribute(Property attribute) {
        val attributeDef = newLinkedHashMap()
        val typeDef = generateTypeDef(attribute, KirraMDDSchemaBuilder.convertType(attribute.type))
        attributeDef.put('type', typeDef)
// TODO        
//        if (attribute.required)
//            attributeDef.put('required', true)
        if (attribute.type.enumeration)
            attributeDef.put('enum', attribute.type.enumerationLiterals.map['''"«it»"'''])
        attributeDef.put('"default"', 
            if (attribute.defaultValue != null) 
                attribute.defaultValue.generateValue
            else if (attribute.required || attribute.type.enumeration)
                // enumeration covers state machines as well
                attribute.type.generateDefaultValue
            else
                null
            )
        '''«attribute.name» : «generatePrimitiveValue(attributeDef)»'''
    }

    def generateSchemaRelationship(Property relationship) {
        val relationshipDef = newLinkedHashMap()
        relationshipDef.put('type', 'Schema.Types.ObjectId')
        relationshipDef.put('ref', '''"«relationship.type.name»"''')
        if (relationship.multivalued)
            relationshipDef.put('"default"', '[]')
        if (relationship.required)
            relationshipDef.put('required', true)
        '''«relationship.name» : «if (relationship.multivalued) #[generatePrimitiveValue(relationshipDef)] else generatePrimitiveValue(relationshipDef)»'''
    }
    
    def generateSubSchema(Property relationship) {
        val properties = (relationship.type as Class).properties.filter[!derived]
        val subSchema = generateSchemaCore(relationship.type as Class, properties)
        '''«relationship.name» : «if (relationship.multivalued) '''[«subSchema»]''' else subSchema»'''
    }

    def generateTypeDef(Property attribute, TypeRef type) {
        switch (type.kind) {
            case Enumeration:
                'String'
            case Primitive:
                switch (type.typeName) {
                    case 'Integer': 'Number'
                    case 'Double': 'Number'
                    case 'Date': 'Date'
                    case 'String' : 'String'
                    case 'Memo' : 'String'
                    case 'Boolean': 'Boolean'
                    default: 'UNEXPECTED TYPE: «type.typeName»'
                }
            default:
                'UNEXPECTED KIND: «type.kind»'
        }
    }
    
    def generateStateMachine(StateMachine stateMachine, Class entity) {
        val stateAttribute = entity.findStateProperties.head
        if (stateAttribute == null) {
            return ''
        }
        val triggersPerEvent = stateMachine.findTriggersPerEvent
        val events = triggersPerEvent.keySet
        val schemaVar = getSchemaVar(entity)
        val needsGuard = stateMachine.vertices.exists[it.outgoings.exists[it.guard != null]]
        '''
            «schemaVar».methods.handleEvent = function (event) {
                console.log("started handleEvent("+ event+"): "+ this);
                «IF (needsGuard)»
                var guard;
                «ENDIF»
                switch (event) {
                    «triggersPerEvent.entrySet.map[generateEventHandler(entity, stateAttribute, it.key, it.value)].join('\n')»
                }
                console.log("completed handleEvent("+ event+"): "+ this);
                
            };
            
            «events.map[event | '''
            «schemaVar».methods.«event.generateEventName.toString.toFirstLower» = function () {
                this.handleEvent('«event.generateEventName»');
            };
            '''].join('')»
        '''
        
    }

    def generateEventHandler(Class entity, Property stateAttribute, Event event, List<Trigger> triggers) {
        '''
        case '«event.generateEventName»' :
            «triggers.map[generateHandlerForTrigger(entity, stateAttribute, it)].join('\n')»
            break;
        '''
    }
    
    def generateHandlerForTrigger(Class entity, Property stateAttribute, Trigger trigger) {
        val transition = trigger.eContainer as Transition
        val originalState = transition.source
        val targetState = transition.target
        '''
        «transition.generateComment»if (this.«stateAttribute.name» == '«originalState.name»') {
            «IF (transition.guard != null)»
            guard = «generatePredicate(transition.guard)»;
            if (guard.call(this)) {
                «generateStateTransition(stateAttribute, originalState, targetState)»
            }
            «ELSE»
            «generateStateTransition(stateAttribute, originalState, targetState)»
            «ENDIF»
        }'''
    }
    
    def generateStateTransition(Property stateAttribute, Vertex originalState, Vertex newState) {
        '''
        «IF (originalState instanceof State)»
            «IF (originalState.exit != null)»
            // on exiting «originalState.name»
            (function() {
                «generateActivity(originalState.exit as Activity)»
            })();
            «ENDIF»
        «ENDIF»
        this.«stateAttribute.name» = '«newState.name»';
        «IF (newState instanceof State)»
            «IF (newState.entry != null)»
            // on entering «newState.name»
            (function() {
                «generateActivity(newState.entry as Activity)»
            })();
            «ENDIF»
        «ENDIF»
        return;
        '''
    }
    
    def generateEventName(Event e) {
        switch (e) {
            CallEvent : e.operation.name
            SignalEvent : e.signal.name
            TimeEvent : '_time'
            AnyReceiveEvent : '_any'
            default : unsupportedElement(e)
        }
    }
    
    
}
