/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The sample app's main view controller.
*/

import UIKit
import RealityKit
import ARKit
import Combine

class CustomSphere: Entity, HasModel {
     required init(color: UIColor, radius: Float) {
       super.init()
       self.components[ModelComponent] = ModelComponent(
         mesh: .generateSphere(radius: radius),
         materials: [SimpleMaterial(
           color: color,
           isMetallic: false)
         ]
       )
     }
    
    required init() {
        fatalError("init() has not been implemented")
    }
}

class ViewController: UIViewController, ARSessionDelegate {

    @IBOutlet var arView: ARView!
    
    @IBOutlet weak var toggleRobotButton: UIButton!
    @IBOutlet weak var jointNamePickerView: UIPickerView!
    
    // The 3D character to display.
    var character: BodyTrackedEntity?
    let characterOffset: SIMD3<Float> = [0, 0, 0] // Offset the character by one meter to the left
    let characterAnchor = AnchorEntity()
    
    let sphereAnchor = AnchorEntity()
    var jointSpheres = [Entity]()
    
    var jointDots = [CAShapeLayer]()
    
    var pickedJoints = [String: Entity]()
    var jointNames = [String]()
    
    var showRobot = false
    
    // A tracked raycast which is used to place the character accurately
    // in the scene wherever the user taps.
    var placementRaycast: ARTrackedRaycast?
    var tapPlacementAnchor: AnchorEntity?
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        jointNamePickerView.dataSource = self
        jointNamePickerView.delegate = self
        
        jointNames.append("Waiting for a body anchor..")
        jointNamePickerView.reloadAllComponents()

        
        arView.session.delegate = self
        
        // If the iOS device doesn't support body tracking, raise a developer error for
        // this unhandled case.
        guard ARBodyTrackingConfiguration.isSupported else {
            fatalError("This feature is only supported on devices with an A12 chip")
        }

        // Run a body tracking configration.
        let configuration = ARBodyTrackingConfiguration()
        arView.session.run(configuration)
        
        arView.scene.addAnchor(characterAnchor)
        arView.scene.addAnchor(sphereAnchor)
        
        // Asynchronously load the 3D character.
        var cancellable: AnyCancellable? = nil
        cancellable = Entity.loadBodyTrackedAsync(named: "character/robot").sink(
            receiveCompletion: { completion in
                if case let .failure(error) = completion {
                    print("Error: Unable to load model: \(error.localizedDescription)")
                }
                cancellable?.cancel()
        }, receiveValue: { (character: Entity) in
            if let character = character as? BodyTrackedEntity {
                // Scale the character to human size
                character.scale = [1.0, 1.0, 1.0]
                self.character = character
                cancellable?.cancel()
            } else {
                print("Error: Unable to load model as BodyTrackedEntity")
            }
        })
    }
    
    @IBAction func showAllJoints3D() {
        guard let anchors = arView.session.currentFrame?.anchors else {return}
        for anchor in anchors {
            if let bodyAnchor = anchor as? ARBodyAnchor, let character = character, character.jointNames.count == bodyAnchor.skeleton.jointModelTransforms.count {

                hideAllJoints3D()
                
                let bodyPosition = simd_make_float3(bodyAnchor.transform.columns.3)
                let bodyOrientation = Transform(matrix: bodyAnchor.transform).rotation
                
                for  i in 0..<bodyAnchor.skeleton.jointModelTransforms.count {
                    let jointName = character.jointName(forPath: character.jointNames[i])
                    if let transform = bodyAnchor.skeleton.modelTransform(for: jointName) {
                        let position = bodyPosition + simd_make_float3(transform.columns.3)
                        let sphere = CustomSphere(color: .blue, radius: 0.05)
                        sphereAnchor.addChild(sphere)
                        sphere.position = position
                        sphere.orientation = bodyOrientation
                        jointSpheres.append(sphere)
                    } else {
                        print("Joint \(jointName) not found by name!")
                    }
                }
            }
        }
    }
    
    func displayJoint(forName name: String) {
        if pickedJoints[name] != nil {
            return
        }
        
        guard let anchors = arView.session.currentFrame?.anchors else {return}
        for anchor in anchors {
            if let bodyAnchor = anchor as? ARBodyAnchor, let character = character, character.jointNames.count == bodyAnchor.skeleton.jointModelTransforms.count {
                
                if let transform = bodyAnchor.skeleton.modelTransform(for: ARSkeleton.JointName(rawValue: name)) {
                    
                    let bodyPosition = simd_make_float3(bodyAnchor.transform.columns.3)
                    let bodyOrientation = Transform(matrix: bodyAnchor.transform).rotation
                    
                    let position = bodyPosition + simd_make_float3(transform.columns.3)
                    let sphere = CustomSphere(color: .systemPink, radius: 0.025)
                    sphereAnchor.addChild(sphere)
                    sphere.position = position
                    sphere.orientation = bodyOrientation
                    pickedJoints[name] = sphere
                    
                    print("Added joint for \(name)")
                } else {
                    print("Joint for \(name) not found!")
                }
            }
        }
    }
    
    @IBAction func showAllJoints2D() {
        guard let anchors = arView.session.currentFrame?.anchors else {return}
        for anchor in anchors {
            if let bodyAnchor = anchor as? ARBodyAnchor, let character = character,
                let frame = arView.session.currentFrame, character.jointNames.count == bodyAnchor.skeleton.jointModelTransforms.count {
                
                hideAllJoints2D()
                
                let bodyPosition = simd_make_float3(bodyAnchor.transform.columns.3)
                
                for transform in bodyAnchor.skeleton.jointModelTransforms {
                    let position = bodyPosition + simd_make_float3(transform.columns.3)
                    let projection = frame.camera.projectPoint([position.x, position.y, bodyPosition.z], orientation: .portrait, viewportSize: view.bounds.size)
                    let shapeLayer = CAShapeLayer();
                    shapeLayer.path = UIBezierPath(ovalIn: CGRect(x: CGFloat(projection.x), y: CGFloat(projection.y), width: 10, height: 10)).cgPath;
                    shapeLayer.fillColor = UIColor.green.cgColor
                    view.layer.addSublayer(shapeLayer)
                    jointDots.append(shapeLayer)
                }
            }
        }
    }
    
    @IBAction func toggleRobotVisibility() {
        showRobot = !showRobot
        if let currentBackgroundImage = toggleRobotButton.currentBackgroundImage {
            if showRobot {
                toggleRobotButton.setBackgroundImage(currentBackgroundImage.withTintColor(.white), for: .normal)
            } else {
                toggleRobotButton.setBackgroundImage(currentBackgroundImage.withTintColor(.black), for: .normal)
                character?.removeFromParent()
            }
        }
    }
    
    @IBAction func hideAllJoints3D() {
        jointSpheres.forEach {
            $0.removeFromParent()
        }
        jointSpheres.removeAll()
    }
    
    @IBAction func hideAllJoints2D() {
        jointDots.forEach {
            $0.removeFromSuperlayer()
        }
        jointDots.removeAll()
    }
    
    @IBAction func removeAllPickedJoints() {
        for joint in pickedJoints {
            joint.value.removeFromParent()
        }
        pickedJoints.removeAll()
    }
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let bodyAnchor = anchor as? ARBodyAnchor else { continue }
            
            // Update the position of the character anchor's position.
            let bodyPosition = simd_make_float3(bodyAnchor.transform.columns.3)
            let bodyOrientation = Transform(matrix: bodyAnchor.transform).rotation
            characterAnchor.position = bodyPosition + characterOffset
            // Also copy over the rotation of the body anchor, because the skeleton's pose
            // in the world is relative to the body anchor's rotation.
            characterAnchor.orientation = bodyOrientation
   
            if let character = character, character.parent == nil {
                // Attach the character to its anchor as soon as
                // 1. the body anchor was detected and
                // 2. the character was loaded.
                
                if showRobot {
                    characterAnchor.addChild(character)
                }
                
                if jointNames.count < character.jointNames.count {
                    jointNames.removeAll()
                    
                    jointNames.append("Select a joint name to display...")
                    character.jointNames.forEach {
                        jointNames.append(character.jointName(forPath: $0).rawValue)
                    }
                    jointNamePickerView.reloadAllComponents()
                }
            }
            
            // update joint spheres, in case they're added
            if let character = character {
                if jointSpheres.count == bodyAnchor.skeleton.jointModelTransforms.count, jointSpheres.count == character.jointNames.count {
                    for  i in 0..<bodyAnchor.skeleton.jointModelTransforms.count {
                        let jointName = character.jointName(forPath: character.jointNames[i])
                        if let transform = bodyAnchor.skeleton.modelTransform(for: jointName) {
                            let position = bodyPosition + simd_make_float3(transform.columns.3)
                            jointSpheres[i].position = position
                            jointSpheres[i].orientation = bodyOrientation
                        }
                    }
                }
                
                // updated joint dots, in case they're added
                if jointDots.count == bodyAnchor.skeleton.jointModelTransforms.count {
                    showAllJoints2D()
                }
                
                // updated picked joints, in case they're added
                if pickedJoints.count > 0 {
                    for joint in pickedJoints {
                        if let transform = bodyAnchor.skeleton.modelTransform(for: ARSkeleton.JointName(rawValue: joint.key)) {
                            let position = bodyPosition + simd_make_float3(transform.columns.3)
                            joint.value.position = position
                            joint.value.orientation = bodyOrientation
                        }
                    }
                }
            }
        }
    }
}

extension BodyTrackedEntity {
    func jointName(forPath path: String) -> ARSkeleton.JointName {
        let splitPath = path.split(separator: "/")
        return ARSkeleton.JointName(rawValue: String(splitPath[splitPath.count - 1]))
    }
}

extension ViewController: UIPickerViewDataSource {
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return jointNames.count
    }
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return jointNames[row]
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        displayJoint(forName: jointNames[row])
    }
    
    
}

extension ViewController: UIPickerViewDelegate {
    
    func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
        return 60
    }
    
}
