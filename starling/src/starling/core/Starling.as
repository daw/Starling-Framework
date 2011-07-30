package starling.core
{
    import flash.display.Stage3D;
    import flash.display3D.Context3D;
    import flash.display3D.Program3D;
    import flash.events.Event;
    import flash.events.KeyboardEvent;
    import flash.events.MouseEvent;
    import flash.events.TouchEvent;
    import flash.geom.Point;
    import flash.geom.Rectangle;
    import flash.ui.Multitouch;
    import flash.ui.MultitouchInputMode;
    import flash.utils.ByteArray;
    import flash.utils.Dictionary;
    import flash.utils.getTimer;
    
    import starling.animation.Juggler;
    import starling.display.*;
    import starling.events.TouchPhase;
    import starling.events.TouchProcessor;
    import starling.utils.*;
    
    public class Starling
    {
        // TODO: clear color buffer with SWF background color
        
        // members
        
        private var mStage3D:Stage3D;
        private var mStage:Stage; // starling.display.stage!
        private var mRootClass:Class;
        private var mJuggler:Juggler;
        private var mStarted:Boolean;        
        private var mSupport:RenderSupport;
        private var mTouchProcessor:TouchProcessor;
        private var mSimulateMultitouch:Boolean;
        private var mEnableErrorChecking:Boolean;
        private var mLastFrameTimestamp:Number;
        private var mViewPort:Rectangle;
        
        private var mContext:Context3D;
        private var mPrograms:Dictionary;
        
        private static var sCurrent:Starling;
        
        // construction
        
        public function Starling(rootClass:Class, stage:flash.display.Stage, 
                                 viewPort:Rectangle=null, stage3D:Stage3D=null,
                                 renderMode:String="auto") 
        {
            if (stage == null) throw new ArgumentError("Stage must not be null");
            if (rootClass == null) throw new ArgumentError("Root class must not be null");
            if (viewPort == null) viewPort = new Rectangle(0, 0, stage.stageWidth, stage.stageHeight);
            if (stage3D == null) stage3D = stage.stage3Ds[0];
            
            mRootClass = rootClass;
            mViewPort = viewPort;
            mStage3D = stage3D;
            mStage = new Stage(viewPort.width, viewPort.height);
            mTouchProcessor = new TouchProcessor(mStage);
            mJuggler = new Juggler();
            mSimulateMultitouch = false;
            mEnableErrorChecking = false;
            mLastFrameTimestamp = getTimer() / 1000.0;
            mPrograms = new Dictionary();
            
            if (sCurrent == null)
                makeCurrent();
            
            // register touch/mouse event handlers            
            var touchEventTypes:Array = Multitouch.supportsTouchEvents ?
                [ TouchEvent.TOUCH_BEGIN, TouchEvent.TOUCH_MOVE, TouchEvent.TOUCH_END ] :
                [ MouseEvent.MOUSE_DOWN, MouseEvent.MOUSE_MOVE, MouseEvent.MOUSE_UP ];            
            for each (var touchEventType:String in touchEventTypes)
                stage.addEventListener(touchEventType, onTouch, false, 0, true);
            
            // register other event handlers
            stage.addEventListener(Event.RESIZE, onResize, false, 0, true);
            stage.addEventListener(Event.ENTER_FRAME, onEnterFrame, false, 0, true);
            stage.addEventListener(KeyboardEvent.KEY_DOWN, onKey, false, 0, true);
            stage.addEventListener(KeyboardEvent.KEY_UP, onKey, false, 0, true);
            
            mStage3D.addEventListener(Event.CONTEXT3D_CREATE, onContextCreated, false, 0, true);
            mStage3D.requestContext3D(renderMode);
        }
        
        public function dispose():void
        {
            for each (var program:Program3D in mPrograms)
                program.dispose();
            
            if (mContext) mContext.dispose();
            if (mTouchProcessor) mTouchProcessor.dispose();
        }
        
        // functions
        
        private function initializeGraphicsAPI():void
        {
            if (mContext) return;            
            
            mContext = mStage3D.context3D;
            mSupport = new RenderSupport(mContext);                        
            mStage3D.x = mViewPort.x;
            mStage3D.y = mViewPort.y;
            mContext.configureBackBuffer(mViewPort.width, mViewPort.height, 1, false);
            mContext.enableErrorChecking = mEnableErrorChecking;
            
            trace("[Starling] Initialization complete.");
            trace("[Starling] Display Driver:" + mContext.driverInfo);
        }
        
        private function initializePrograms():void
        {
            Quad.registerPrograms(this);
            Image.registerPrograms(this);
        }
        
        private function initializeRoot():void
        {
            if (mStage.numChildren > 0) return;
            
            var rootObject:DisplayObject = new mRootClass();
            if (rootObject == null) throw new Error("Invalid root class: " + mRootClass);
            mStage.addChild(rootObject);
        }
        
        public function makeCurrent():void
        {
            sCurrent = this;
        }
        
        public function start():void { mStarted = true; }
        public function stop():void { mStarted = false; }
        
        private function render():void
        {
            if (mContext == null) return;
            
            var now:Number = getTimer() / 1000.0;
            var passedTime:Number = now - mLastFrameTimestamp;
            mLastFrameTimestamp = now;
            
            mStage.advanceTime(passedTime);
            mJuggler.advanceTime(passedTime);
            mTouchProcessor.advanceTime(passedTime);
            
            mSupport.setupOrthographicRendering(mViewPort.width, mViewPort.height);
            mSupport.setupDefaultBlendFactors();
            
            mContext.clear();            
            mStage.render(mSupport);            
            mContext.present();
        }
        
        // event handlers
        
        private function onResize(event:Event):void
        {
            // TODO
        }
        
        private function onContextCreated(event:Event):void
        {            
            initializeGraphicsAPI();
            initializePrograms();
            initializeRoot();
            
            mTouchProcessor.simulateMultitouch = mSimulateMultitouch;
        }
        
        private function onEnterFrame(event:Event):void
        {
            if (mStarted) render();           
        }
        
        private function onKey(event:KeyboardEvent):void
        {
            mStage.broadcastEvent(new starling.events.KeyboardEvent(
                event.type, event.charCode, event.keyCode, event.keyLocation, 
                event.ctrlKey, event.altKey, event.shiftKey));
        }
        
        private function onTouch(event:Event):void
        {
            var position:Point;
            var phase:String;
            var touchID:int;
            
            if (event is MouseEvent)
            {
                var mouseEvent:MouseEvent = event as MouseEvent;
                position = convertPosition(new Point(mouseEvent.stageX, mouseEvent.stageY));
                phase = getPhaseFromMouseEvent(mouseEvent);
                touchID = 0;
            }
            else
            {
                var touchEvent:TouchEvent = event as TouchEvent;
                position = convertPosition(new Point(touchEvent.stageX, touchEvent.stageY));
                phase = getPhaseFromTouchEvent(touchEvent);
                touchID = touchEvent.touchPointID;
            }
            
            mTouchProcessor.enqueue(touchID, phase, position.x, position.y);
            
            function convertPosition(globalPos:Point):Point
            {
                return new Point(
                    (globalPos.x - mViewPort.x) * (mViewPort.width / mStage.stageWidth),
                    (globalPos.y - mViewPort.y) * (mViewPort.height / mStage.stageHeight));
            }
            
            function getPhaseFromMouseEvent(event:MouseEvent):String
            {
                switch (event.type)
                {
                    case MouseEvent.MOUSE_DOWN: return TouchPhase.BEGAN; break;
                    case MouseEvent.MOUSE_UP:   return TouchPhase.ENDED; break;
                    case MouseEvent.MOUSE_MOVE: 
                        return mouseEvent.buttonDown ? TouchPhase.MOVED : TouchPhase.HOVER; 
                        break;
                    default: return null;
                }
            }
             
            function getPhaseFromTouchEvent(event:TouchEvent):String
            {
                switch (event.type)
                {
                    case TouchEvent.TOUCH_BEGIN: return TouchPhase.BEGAN; break;
                    case TouchEvent.TOUCH_MOVE:  return TouchPhase.MOVED; break;
                    case TouchEvent.TOUCH_END:   return TouchPhase.ENDED; break;
                    default: return null;
                }
            }
        }
        
        // program management
        
        public function registerProgram(name:String, vertexProgram:ByteArray, fragmentProgram:ByteArray):void
        {
            if (mPrograms.hasOwnProperty(name))
                throw new Error("Another program with this name is already registered");
            
            var program:Program3D = mContext.createProgram();
            program.upload(vertexProgram, fragmentProgram);            
            mPrograms[name] = program;
        }
        
        public function deleteProgram(name:String):void
        {
            var program:Program3D = getProgram(name);            
            if (program)
            {                
                program.dispose();
                delete mPrograms[name];
            }
        }
        
        public function getProgram(name:String):Program3D
        {
            return mPrograms[name] as Program3D;
        }
        
        // properties
        
        public function get isStarted():Boolean { return mStarted; }
        
        public function get juggler():Juggler { return mJuggler; }
        public function get context():Context3D { return mContext; }
        
        public function get simulateMultitouch():Boolean { return mSimulateMultitouch; }
        public function set simulateMultitouch(value:Boolean):void
        {
            mSimulateMultitouch = value;
            if (mContext) mTouchProcessor.simulateMultitouch = value;
        }
        
        public function get enableErrorChecking():Boolean { return mEnableErrorChecking; }
        public function set enableErrorChecking(value:Boolean):void 
        { 
            mEnableErrorChecking = value;
            if (mContext) mContext.enableErrorChecking = value; 
        }
        
        // static properties
        
        public static function get current():Starling { return sCurrent; }
        
        public static function get context():Context3D { return sCurrent.context; }
        public static function get juggler():Juggler { return sCurrent.juggler; }
        
        public static function get multitouchEnabled():Boolean 
        { 
            return Multitouch.inputMode == MultitouchInputMode.TOUCH_POINT;
        }
        
        public static function set multitouchEnabled(value:Boolean):void
        {            
            Multitouch.inputMode = value ? MultitouchInputMode.TOUCH_POINT :
                                           MultitouchInputMode.NONE;
        }
    }
}