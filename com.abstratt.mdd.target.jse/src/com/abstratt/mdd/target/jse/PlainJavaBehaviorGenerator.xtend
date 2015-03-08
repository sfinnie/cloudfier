package com.abstratt.mdd.target.jse

import com.abstratt.mdd.core.IRepository
import com.abstratt.mdd.core.util.MDDExtensionUtils
import com.abstratt.mdd.target.jse.IBehaviorGenerator.IExecutionContext
import java.util.Arrays
import java.util.Deque
import java.util.LinkedList
import java.util.List
import java.util.concurrent.atomic.AtomicInteger
import org.eclipse.uml2.uml.Action
import org.eclipse.uml2.uml.Activity
import org.eclipse.uml2.uml.AddStructuralFeatureValueAction
import org.eclipse.uml2.uml.AddVariableValueAction
import org.eclipse.uml2.uml.CallOperationAction
import org.eclipse.uml2.uml.Classifier
import org.eclipse.uml2.uml.Clause
import org.eclipse.uml2.uml.ConditionalNode
import org.eclipse.uml2.uml.CreateLinkAction
import org.eclipse.uml2.uml.CreateObjectAction
import org.eclipse.uml2.uml.DataType
import org.eclipse.uml2.uml.DestroyLinkAction
import org.eclipse.uml2.uml.DestroyObjectAction
import org.eclipse.uml2.uml.InputPin
import org.eclipse.uml2.uml.LinkEndData
import org.eclipse.uml2.uml.LiteralBoolean
import org.eclipse.uml2.uml.Operation
import org.eclipse.uml2.uml.Parameter
import org.eclipse.uml2.uml.Property
import org.eclipse.uml2.uml.ReadExtentAction
import org.eclipse.uml2.uml.ReadLinkAction
import org.eclipse.uml2.uml.ReadSelfAction
import org.eclipse.uml2.uml.ReadStructuralFeatureAction
import org.eclipse.uml2.uml.ReadVariableAction
import org.eclipse.uml2.uml.SendSignalAction
import org.eclipse.uml2.uml.StructuredActivityNode
import org.eclipse.uml2.uml.TestIdentityAction
import org.eclipse.uml2.uml.Type
import org.eclipse.uml2.uml.ValueSpecificationAction
import org.eclipse.uml2.uml.Variable
import org.eclipse.uml2.uml.VariableAction

import static extension com.abstratt.kirra.mdd.core.KirraHelper.*
import static extension com.abstratt.kirra.mdd.core.KirraHelper.*
import static extension com.abstratt.mdd.core.util.ActivityUtils.*
import static extension com.abstratt.mdd.core.util.FeatureUtils.*
import static extension com.abstratt.mdd.core.util.MDDExtensionUtils.*
import static extension com.abstratt.mdd.core.util.StateMachineUtils.*

class PlainJavaBehaviorGenerator extends PlainJavaGenerator implements IBehaviorGenerator {
    
    Deque<IExecutionContext> contextStack = new LinkedList(Arrays.asList(new SimpleContext("this")))

    new(IRepository repository) {
        super(repository)
    }
    
    override enterContext(IExecutionContext context) {
        contextStack.push(context)
    }
    
    override leaveContext(IExecutionContext context) {
        val top = contextStack.peek
        if (context != top)
            throw new IllegalStateException
        contextStack.pop    
    }
    
    override getContext() {
        contextStack.peek
    }

    override CharSequence generateActivity(Activity activity) {
        '''
            «generateActivityRootAction(activity)»
        '''
    }
    
    def dispatch CharSequence generateAction(Action toGenerate) {
        generateActionProper(toGenerate)
    }

    def generateActivityRootAction(Activity activity) {
        val rootActionGenerated = generateAction(activity.rootAction)
        '''
            «rootActionGenerated»
        '''
    }

    def dispatch CharSequence generateAction(Void input) {
        throw new NullPointerException;
    }

    def dispatch CharSequence generateAction(InputPin input) {
        generateAction(input.sourceAction)
    }

    def CharSequence generateActionProper(Action toGenerate) {
        doGenerateAction(toGenerate)
    }

    def generateStatement(Action statementAction) {
        val isBlock = if (statementAction instanceof StructuredActivityNode)
                !MDDExtensionUtils.isCast(statementAction) && !statementAction.objectInitialization
        val generated = generateAction(statementAction)
        if (isBlock)
            // actually a block
            return generated

        // else generate as a statement
        '''«generated»;'''
    }

    def dispatch CharSequence doGenerateAction(Action action) {

        // should never pick this version - a more specific variant should exist for all supported actions
        unsupported(action.eClass.name)
    }

    def dispatch CharSequence doGenerateAction(AddVariableValueAction action) {
        generateAddVariableValueAction(action)
    }

    def generateAddVariableValueAction(AddVariableValueAction action) {
        if (action.variable.name == '') 
            action.generateAddVariableValueActionAsReturn
        else
            action.generateAddVariableValueActionAsAssignment
    }
    
    def generateAddVariableValueActionAsReturn(AddVariableValueAction action) {
        '''return «generateAction(action.value).toString.trim»'''
    }

    def generateAddVariableValueActionAsAssignment(AddVariableValueAction action) {
        '''«action.variable.name» = «generateAction(action.value)»'''
    }    

    def dispatch CharSequence doGenerateAction(ReadExtentAction action) {
        generateReadExtentAction(action)
    }

    def CharSequence generateReadExtentAction(ReadExtentAction action) {
        throw new UnsupportedOperationException("ReadExtent not supported")
    }

    def dispatch CharSequence doGenerateAction(TestIdentityAction action) {
        '''«generateTestidentityAction(action)»'''
    }

    def generateTestidentityAction(TestIdentityAction action) {
        '''«generateAction(action.first)» == «generateAction(action.second)»'''.parenthesize(action)
    }

    def dispatch CharSequence doGenerateAction(DestroyLinkAction action) {
        generateDestroyLinkAction(action)
    }

    def generateDestroyLinkAction(DestroyLinkAction action) {
        generateUnsetLinkEnd(action.endData)
    }

    def generateUnsetLinkEnd(List<LinkEndData> sides) {
        val thisEnd = sides.get(0).end
        val otherEnd = sides.get(1).end
        val thisEndAction = sides.get(0).value
        val otherEndAction = sides.get(1).value
        '''
        «generateLinkDestruction(otherEndAction, thisEnd, thisEndAction, otherEnd, true)»
        «generateLinkDestruction(thisEndAction, otherEnd, otherEndAction, thisEnd, false)»'''
    }

    def generateLinkDestruction(InputPin otherEndAction, Property thisEnd, InputPin thisEndAction, Property otherEnd,
        boolean addSemiColon) {
        if(!thisEnd.navigable) return ''
        generateLinkDestruction(otherEndAction.generateAction, thisEnd, generateAction(thisEndAction), otherEnd,
            addSemiColon)
    }

    def generateLinkDestruction(CharSequence targetObject, Property thisEnd, CharSequence otherObject, Property otherEnd,
        boolean addSemiColon) {
        if(!thisEnd.navigable) return ''
        '''«targetObject».«thisEnd.name»«IF thisEnd.multivalued».remove(«otherObject»)«ELSE» = null«ENDIF»«IF addSemiColon &&
            otherEnd.navigable»;«ENDIF»'''
    }

    def dispatch CharSequence doGenerateAction(CreateLinkAction action) {
        generateCreateLinkAction(action)
    }

    def generateCreateLinkAction(CreateLinkAction action) {
        generateSetLinkEnd(action.endData)
    }

    def generateSetLinkEnd(List<LinkEndData> sides) {
        val thisEnd = sides.get(0).end
        val otherEnd = sides.get(1).end
        val thisEndAction = sides.get(0).value
        val otherEndAction = sides.get(1).value
        '''
        
        «generateLinkCreation(otherEndAction, thisEnd, thisEndAction, otherEnd, true)»
        «generateLinkCreation(thisEndAction, otherEnd, otherEndAction, thisEnd, false)»'''
    }

    def CharSequence generateLinkCreation(InputPin otherEndAction, Property thisEnd, InputPin thisEndAction,
        Property otherEnd, boolean addSemiColon) {
        if (!thisEnd.navigable)
            return ''
        val targetObject = generateAction(otherEndAction)
        val otherObject = generateAction(thisEndAction)
        generateLinkCreation(targetObject, thisEnd, otherObject, otherEnd, addSemiColon)
    }

    def generateLinkCreation(CharSequence targetObject, Property thisEnd, CharSequence otherObject, Property otherEnd,
        boolean addSemiColon) {
        if(!thisEnd.navigable) return ''
        '''«targetObject».«thisEnd.name»«IF thisEnd.multivalued».add(«otherObject»)«ELSE» = «otherObject»«ENDIF»«IF addSemiColon &&
            otherEnd.navigable»;«ENDIF»'''
    }

    def dispatch CharSequence doGenerateAction(CallOperationAction action) {
        generateCallOperationAction(action)
    }

    protected def CharSequence generateCallOperationAction(CallOperationAction action) {
        val operation = action.operation

        if (isBasicTypeOperation(operation))
            generateBasicTypeOperationCall(action)
        else {
            val target = 
                if(operation.static) {
                    val targetClassifier = action.operationTarget
                    if (targetClassifier.entity)
                        generateProviderReference(action.actionActivity.behaviorContext, targetClassifier)
                    else
                        targetClassifier.name 
                } else 
                    generateAction(action.target)
            generateOperationCall(target, action)
        }
    }
    
    def generateProviderReference(Classifier context, Classifier provider) {
        '''new «provider.toJavaType»Service()'''
    }

    def generateOperationCall(CharSequence target, CallOperationAction action) {
        '''«target».«action.operation.name»(«action.arguments.map[generateAction].join(', ')»)'''
    }

    def findOperator(Type type, Operation operation) {
        return switch (operation.name) {
            case 'add':
                '+'
            case 'subtract':
                '-'
            case 'multiply':
                '*'
            case 'divide':
                '/'
            case 'minus':
                '-'
            case 'and':
                '&&'
            case 'or':
                '||'
            case 'not':
                '!'
            case 'lowerThan':
                if(type.javaPrimitive) '<'
            case 'greaterThan':
                if(type.javaPrimitive) '>'
            case 'lowerOrEquals':
                if(type.javaPrimitive) '<='
            case 'greaterOrEquals':
                if(type.javaPrimitive) '>='
            case 'same':
                '=='
            default:
                if (type instanceof DataType)
                    switch (operation.name) {
                        case 'equals': '=='
                    }
        }
    }

    def Classifier getOperationTarget(CallOperationAction action) {
        return if(action.target != null && !action.target.multivalued) action.target.type as Classifier else action.
            operation.owningClassifier
    }

    def boolean needsParenthesis(Action action) {
        val targetAction = action.targetAction
        return if (targetAction instanceof CallOperationAction)
            // operators require the expression to be wrapped in parentheses
            targetAction.operation.isBasicTypeOperation && findOperator(targetAction.operationTarget, targetAction.operation) != null
        else
            false
    }

    def parenthesize(CharSequence toWrap, Action action) {
        val needsParenthesis = action.needsParenthesis
        if (needsParenthesis)
            '''(«toWrap»)'''
        else
            toWrap
    }

    def CharSequence generateBasicTypeOperationCall(CallOperationAction action) {
        val targetType = action.operationTarget
        val operation = action.operation
        val operator = findOperator(action.operationTarget, action.operation)
        if (operator != null) {
            switch (action.arguments.size()) {
                // unary operator
                case 0:
                    '''«operator»«generateAction(action.target)»'''.parenthesize(action)
                case 1:
                    '''«generateAction(action.target)» «operator» «generateAction(action.arguments.head)»'''.
                        parenthesize(action)
                default: unsupported('''operation «action.operation.name»''')
            }
        } else
            switch (action.operation.owningClassifier.name) {
                case 'Primitive':
                    switch (operation.name) {
                        case 'equals': '''«action.target.generateAction».equals(«action.arguments.head.generateAction»)'''
                        case 'notEquals': '''!«action.target.generateAction».equals(«action.arguments.head.
                            generateAction»)'''
                        case 'lowerThan': '''«action.target.generateAction».compareTo(«action.arguments.head.
                            generateAction») < 0'''
                        case 'greaterThan': '''«action.target.generateAction».compareTo(«action.arguments.head.
                            generateAction») <= 0'''
                        case 'lowerOrEquals': '''«action.target.generateAction».compareTo(«action.arguments.head.
                            generateAction») >= 0'''
                        case 'greaterOrEquals': '''«action.target.generateAction».compareTo(«action.arguments.head.
                            generateAction») > 0'''
                        default: unsupported('''Primitive operation «operation.name»''')
                    }
                case 'Date':
                    switch (operation.name) {
                        case 'year':
                            '''«generateAction(action.target)».getYear() + 1900L'''.parenthesize(action)
                        case 'month': '''«generateAction(action.target)».getMonth()'''
                        case 'day': '''«generateAction(action.target)».getDate()'''
                        case 'today':
                            'java.sql.Date.valueOf(java.time.LocalDate.now())'
                        case 'now':
                            'new Date()'
                        case 'transpose': '''new Date(«generateAction(action.target)».getTime() + «generateAction(
                            action.arguments.head)»)'''
                        case 'differenceInDays': '''(«generateAction(action.arguments.head)».getTime() - «generateAction(
                            action.target)».getTime()) / (1000*60*60*24)'''
                        default: unsupported('''Date operation «operation.name»''')
                    }
                case 'Duration': {
                    val period = switch (operation.name) {
                        case 'days': '* 1000 * 60 * 60 * 24'
                        case 'hours': '* 1000 * 60 * 60'
                        case 'minutes': '* 1000 * 60'
                        case 'seconds': '* 1000'
                        case 'milliseconds': ''
                        default: unsupported('''Duration operation: «operation.name»''')
                    }
                    '''«generateAction(action.arguments.head)»«period» /*«operation.name»*/'''
                }
                case 'Memo': {
                    switch (operation.name) {
                        case 'fromString': generateAction(action.arguments.head)
                        default: unsupported('''Memo operation: «operation.name»''')
                    }
                }
                case 'Collection': {
                    generateCollectionOperationCall(action)
                }
                case 'Sequence': {
                    switch (operation.name) {
                        case 'head': '''«generateAction(action.target)».stream().findFirst().«IF action.operation.
                            getReturnResult.lowerBound == 0»orElse(null)«ELSE»get()«ENDIF»'''
                        default: '''«if(operation.getReturnResult != null) 'null' else ''» /*«unsupported('''Sequence operation: «operation.name»''')»*/'''
                    }
                }
                case 'Grouping': {
                    switch (operation.name) {
                        case 'groupCollect': generateGroupingGroupCollect(action)
                        default: '''«if(operation.getReturnResult != null) 'null' else ''» /*«unsupported('''Sequence operation: «operation.name»''')»*/'''
                    }
                }
                case 'System': {
                    switch (operation.name) {
                        case 'user': '''null /* TBD */'''
                        default: unsupported('''System operation: «operation.name»''')
                    }
                }
                default: unsupported('''classifier «targetType.name» - operation «operation.name»''')
            }
    }

    def generateCollectionOperationCall(CallOperationAction action) {
        val operation = action.operation
        switch (operation.name) {
            case 'size':
                '''«generateAction(action.target)».size()'''.parenthesize(action)
            case 'includes': '''«generateAction(action.target)».contains(«action.arguments.head.generateAction»)'''
            case 'isEmpty': '''«generateAction(action.target)».isEmpty()'''
            case 'sum':
                generateCollectionSum(action)
            case 'one':
                generateCollectionOne(action)
            case 'any':
                generateCollectionAny(action)
            case 'asSequence': '''«IF !action.target.ordered»new ArrayList<«action.target.type.toJavaType»>(«ENDIF»«action.
                target.generateAction»«IF !action.target.ordered»)«ENDIF»'''
            case 'forEach':
                generateCollectionForEach(action)
            case 'select':
                generateCollectionSelect(action)
            case 'collect':
                generateCollectionCollect(action)
            case 'reduce':
                generateCollectionReduce(action)
            case 'groupBy':
                generateCollectionGroupBy(action)
            default: '''«if(operation.getReturnResult != null) 'null' else ''» /*«unsupported('''Collection operation: «operation.name»''')»*/'''
        }
    }

    def CharSequence generateCollectionReduce(CallOperationAction action) {
        val closure = action.arguments.get(0).sourceClosure
        val initialValue = action.arguments.get(1)

        // workaround forJDK bug 8058283
        val cast = if (action.results.head.type.javaPrimitive) '''(«action.results.head.type.toJavaType») ''' else ''
        '''«cast»«action.target.generateAction».stream().reduce(«initialValue.generateAction», «closure.
            generateActivityAsExpression(true, closure.closureInputParameters.reverseView).toString.trim», null)'''
    }

    def CharSequence generateCollectionSum(CallOperationAction action) {
        val closure = action.arguments.get(0).sourceClosure
        val isDouble = closure.closureReturnParameter.type.name == 'Double'
        '''«action.target.generateAction».stream().mapTo«IF isDouble»Double«ELSE»Long«ENDIF»(«closure.
            generateActivityAsExpression(true).toString.trim»).sum()'''
    }

    def CharSequence generateCollectionForEach(CallOperationAction action) {
        val closure = action.arguments.get(0).sourceClosure
        '''«action.target.generateAction».forEach(«closure.generateActivityAsExpression(true)»)'''
    }

    def CharSequence generateCollectionCollect(CallOperationAction action) {
        val closure = action.arguments.get(0).sourceClosure
        val collectionGeneralType = action.operation.getReturnResult().toJavaGeneralCollection
        '''«action.target.generateAction».stream().map(«closure.generateActivityAsExpression(true)»).collect(Collectors.toList())'''
    }

    def CharSequence generateCollectionSelect(CallOperationAction action) {
        val closure = action.arguments.get(0).sourceClosure
        val collectionGeneralType = action.operation.getReturnResult().toJavaGeneralCollection
        '''«action.target.generateAction».stream().filter(«closure.generateActivityAsExpression(true)»).collect(Collectors.toList())'''
    }

    def CharSequence generateCollectionGroupBy(CallOperationAction action) {
        val closure = action.arguments.get(0).sourceClosure
        '''«action.target.generateAction».stream().collect(Collectors.groupingBy(«closure.
            generateActivityAsExpression(true)»))'''
    }

    def CharSequence generateCollectionAny(CallOperationAction action) {
        val closure = action.arguments.get(0).sourceClosure
        '''«action.target.generateAction».stream().filter(«closure.generateActivityAsExpression(true)»).findFirst().«IF action.
            operation.getReturnResult.lowerBound == 0»orElse(null)«ELSE»get()«ENDIF»'''
    }

    def CharSequence generateCollectionOne(CallOperationAction action) {
        '''«action.target.generateAction».stream().findFirst().«IF action.operation.getReturnResult.lowerBound == 0»orElse(null)«ELSE»get()«ENDIF»'''
    }

    def CharSequence generateGroupingGroupCollect(CallOperationAction action) {
        val closure = action.arguments.get(0).sourceClosure
        val collectionGeneralType = action.operation.getReturnResult().toJavaGeneralCollection
        '''«action.target.generateAction».values().stream().map(«closure.generateActivityAsExpression(true)»).collect(Collectors.toList())'''
    }

    def dispatch CharSequence doGenerateAction(ConditionalNode node) {
        val clauses = node.clauses
        val clauseCount = clauses.size()
        val current = new AtomicInteger(0)
        val generateClause = [ Clause clause |
            val lastClause = current.incrementAndGet() == clauseCount
            '''
            «generateClauseTest(clause.tests.head as Action, lastClause)» {
                «(clause.bodies.head as Action).generateAction»
            }'''
        ]
        '''«clauses.map[generateClause.apply(it)].join(' else ')»'''
    }

    def generateClauseTest(Action test, boolean lastTest) {
        if (lastTest)
            if (test instanceof ValueSpecificationAction)
                if (test.value instanceof LiteralBoolean)
                    if (test.value.booleanValue)
                        return ''
        '''if («test.generateAction»)'''
    }

    def dispatch CharSequence doGenerateAction(StructuredActivityNode node) {
        val container = node.eContainer

        // avoid putting a comma at a conditional node clause test 
        if (container instanceof ConditionalNode)
            if (container.clauses.exists[tests.contains(node)])
                return '''«node.findStatements.head.generateAction»'''

        // default path, generate as a statement
        if (MDDExtensionUtils.isCast(node))
            generateStructuredActivityNodeAsCast(node)
        else if (node.objectInitialization)
            generateStructuredActivityNodeObjectInitialization(node)
        else
            generateStructuredActivityNodeAsBlock(node)
    }

    def generateStructuredActivityNodeAsCast(StructuredActivityNode node) {
        if (!(node.inputs.head.sourceAction.objectInitialization)) {
            '''(«node.outputs.head.toJavaType») «node.sourceAction.generateAction»'''.parenthesize(node)
        } else {
            val classifier = node.outputs.head.type
            val tupleType = classifier.toJavaType
            generateConstructorInvocation(tupleType, node.sourceAction.inputs)
        }
    }

    def generateStructuredActivityNodeAsBlock(StructuredActivityNode node) {
        '''«generateVariables(node)»«node.findTerminals.map[generateStatement].join('\n')»'''
    }

    def generateVariables(StructuredActivityNode node) {
        generateVariableBlock(node.variables)
    }

    def generateVariableBlock(Iterable<Variable> variables) {
        if(variables.empty) '' else variables.map['''«toJavaType» «name»;'''].join('\n') + '\n'
    }

    def CharSequence generateStructuredActivityNodeObjectInitialization(StructuredActivityNode node) {
        val classifier = node.outputs.head.type
        val tupleType = classifier.toJavaType
        generateConstructorInvocation(tupleType, node.inputs)
    }

    def CharSequence generateConstructorInvocation(String classname, List<InputPin> sources) {
        '''
            new «classname»(
                «sources.generateMany(['''«it.generateAction»'''], ',\n')»
            )
        '''
    }

    def dispatch CharSequence doGenerateAction(SendSignalAction action) {
        generateSendSignalAction(action)
    }

    def generateSendSignalAction(SendSignalAction action) {
        val signalName = action.signal.name
        
        // TODO - this is a temporary implementation
        val targetClassifier = action.target.type as Classifier
        if (targetClassifier.entity && !targetClassifier.findStateProperties.empty) {
            val stateMachine = targetClassifier.findStateProperties.head 
            '''«action.target.generateAction».handleEvent(«action.target.toJavaType».«stateMachine.name.toFirstUpper»Event.«signalName»)'''
        }
    }

    def dispatch CharSequence doGenerateAction(ReadLinkAction action) {
        generateReadLinkAction(action)
    }

    def generateReadLinkAction(ReadLinkAction action) {
        val fedEndData = action.endData.get(0)
        val target = fedEndData.value
        '''«generateTraverseRelationshipAction(target, fedEndData.end.otherEnd)»'''
    }

    def generateTraverseRelationshipAction(InputPin target, Property property) {
        generateFeatureAccess(target, property, property.derived)
    }

    def dispatch CharSequence doGenerateAction(ReadStructuralFeatureAction action) {
        generateReadStructuralFeatureAction(action)
    }

    def generateReadStructuralFeatureAction(ReadStructuralFeatureAction action) {
        val feature = action.structuralFeature as Property
        if (feature.relationship)
            return generateTraverseRelationshipAction(action.object, feature)
        val computed = feature.derived
        val target = action.object
        generateFeatureAccess(target, feature, computed)
    }
    
    def generateFeatureAccess(InputPin target, Property feature, boolean computed) {
        val clazz = feature.owningClassifier
        val targetString = if(target == null) clazz.name else generateAction(target)
        val featureAccess = if (computed) '''«feature.generateAccessorName»()''' else feature.name
        '''«targetString».«featureAccess»'''
    }

    def dispatch CharSequence doGenerateAction(AddStructuralFeatureValueAction action) {
        generateAddStructuralFeatureValueAction(action)
    }

    def generateAddStructuralFeatureValueAction(AddStructuralFeatureValueAction action) {
        val target = action.object
        val value = action.value
        val asProperty = action.structuralFeature as Property
        val featureName = action.structuralFeature.name
        if (action.object != null && asProperty.likeLinkRelationship)
            return if (value.nullValue)
                action.generateAddStructuralFeatureValueActionAsUnlinking
            else
                action.generateAddStructuralFeatureValueActionAsLinking

        '''«generateAction(target)».«featureName» = «generateAction(value)»'''
    }

    def generateAddStructuralFeatureValueActionAsLinking(AddStructuralFeatureValueAction action) {
        val asProperty = action.structuralFeature as Property
        val thisEnd = asProperty
        val otherEnd = asProperty.otherEnd
        val thisEndAction = action.value
        val otherEndAction = action.object
        '''
            «generateLinkCreation(otherEndAction, thisEnd, thisEndAction, otherEnd, true)»
            «generateLinkCreation(thisEndAction, otherEnd, otherEndAction, thisEnd, false)»
        '''.toString.trim
    }

    def generateAddStructuralFeatureValueActionAsUnlinking(AddStructuralFeatureValueAction action) {
        val asProperty = action.structuralFeature as Property
        val thisEnd = asProperty
        val otherEnd = asProperty.otherEnd
        val thisEndAction = action.value
        val otherEndAction = action.object
        '''
            «generateLinkDestruction('''«otherEndAction.generateAction».«thisEnd.name»''', otherEnd,
                otherEndAction.generateAction, thisEnd, true)»
            «generateLinkDestruction(otherEndAction.generateAction, thisEnd, thisEndAction.generateAction, otherEnd, false)»
        '''.toString.trim
    }

    def dispatch CharSequence doGenerateAction(ValueSpecificationAction action) {
        '''«action.value.generateValue(false)»'''
    }

    def dispatch CharSequence doGenerateAction(CreateObjectAction action) {
        generateCreateObjectAction(action)
    }

    def generateCreateObjectAction(CreateObjectAction action) {
        '''new «action.classifier.name»()'''
    }

    def dispatch CharSequence doGenerateAction(DestroyObjectAction action) {
        generateDestroyObjectAction(action)
    }

    def generateDestroyObjectAction(DestroyObjectAction action) {
        '''«action.target.generateAction» = null /* destroy */'''
    }

    def dispatch CharSequence doGenerateAction(ReadVariableAction action) {
        generateReadVariableValueAction(action)
    }

    def generateReadVariableValueAction(ReadVariableAction action) {
        '''«action.variable.name»'''
    }

    def dispatch CharSequence doGenerateAction(ReadSelfAction action) {
        generateReadSelfAction(action)
    }

    def CharSequence generateReadSelfAction(ReadSelfAction action) {
        contextStack.peek.generateCurrentReference
    }
    
    override CharSequence generateActivityAsExpression(Activity toGenerate) {
        return this.generateActivityAsExpression(toGenerate, false, Arrays.<Parameter> asList());
    }

    override generateActivityAsExpression(Activity toGenerate, boolean asClosure) {
        generateActivityAsExpression(toGenerate, asClosure, toGenerate.closureInputParameters)
    }

    override generateActivityAsExpression(Activity toGenerate, boolean asClosure, List<Parameter> parameters) {
        val statements = toGenerate.rootAction.findStatements
        if (statements.size != 1)
            throw new IllegalArgumentException("Single statement activity expected")
        val singleStatement = statements.head
        val isReturnValue = singleStatement instanceof AddVariableValueAction &&
            (singleStatement as VariableAction).variable.isReturnVariable
        val expressionRoot = if(isReturnValue) singleStatement.sourceAction else singleStatement
        if (asClosure) {
            val needParenthesis = parameters.size() != 1
            return '''
            «IF needParenthesis»(«ENDIF»«parameters.generateMany([name], ', ')»«IF needParenthesis»)«ENDIF» -> «IF !isReturnValue»{«ENDIF»
                «expressionRoot.generateAction»«IF !isReturnValue»;«ENDIF»
            «IF !isReturnValue»}«ENDIF»'''
        }
        expressionRoot.generateAction
    }

}
