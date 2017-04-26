//
//  DragDropCollectionView.swift
//  DragDrop
//
//  Created by Lior Neu-ner on 2014/12/30.
//  Copyright (c) 2014 LiorN. All rights reserved.

import UIKit

@objc public protocol DragDropCollectionViewDelegate {
    func dragDropCollectionViewApprovedTargetIndexPath(_ targetIndexPath: NSIndexPath) -> NSIndexPath
    func dragDropCollectionViewDidMoveCellFrom(initialIndexPath: NSIndexPath, to newIndexPath: NSIndexPath)
    @objc optional func dragDropCollectionViewShouldDraggingBeginWithCellAt(indexPath: NSIndexPath) -> Bool
    @objc optional func dragDropCollectionViewDraggingDidEndForCellAtIndexPath(indexPath: NSIndexPath)
}

public class DragDropCollectionView: UICollectionView, UIGestureRecognizerDelegate {
    weak var draggingDelegate: DragDropCollectionViewDelegate?
    
    var longPressRecognizer: UILongPressGestureRecognizer = {
        let longPressRecognizer = UILongPressGestureRecognizer()
        longPressRecognizer.delaysTouchesBegan = false
        longPressRecognizer.cancelsTouchesInView = false
        longPressRecognizer.numberOfTouchesRequired = 1
        longPressRecognizer.minimumPressDuration = 0.1
        longPressRecognizer.allowableMovement = 10.0
        return longPressRecognizer
    }()
    
    private var draggedCellIndexPath: NSIndexPath?
    var draggingView: UIView?
    private var touchOffsetFromCenterOfCell: CGPoint?
    var isWiggling = false
    private let pingInterval = 0.3
    var isAutoScrolling = false
    
    var excludedFromWiggle = [IndexPath]()
    fileprivate func isNotExcluded(_ excluded: [IndexPath], cell: UICollectionViewCell) -> Bool {
        var isExcluded = false
        excluded.forEach() {
            if let row = self.indexPath(for: cell)?.row {
                if $0.row == row {
                    isExcluded = true
                }
            }
        }
        return !isExcluded
    }

    
    override public var intrinsicContentSize: CGSize {
        self.layoutIfNeeded()
        return CGSize(width: UIViewNoIntrinsicMetric, height: self.contentSize.height)
    }
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }
    
    override init(frame: CGRect, collectionViewLayout layout: UICollectionViewLayout) {
        super.init(frame: frame, collectionViewLayout: layout)
        commonInit()
    }
    
    private func commonInit() {
        longPressRecognizer.addTarget(self, action: #selector(DragDropCollectionView.handleLongPress))
        longPressRecognizer.isEnabled = false
        self.addGestureRecognizer(longPressRecognizer)
        
    }
    
    override public func reloadData() {
        super.reloadData()
        self.invalidateIntrinsicContentSize()
    }
    
    public func handleLongPress(longPressRecognizer: UILongPressGestureRecognizer) {
        let touchLocation = longPressRecognizer.location(in: self)
        
        switch (longPressRecognizer.state) {
        case UIGestureRecognizerState.began:
            if let draggedCellIndexPath = indexPathForItem(at: touchLocation) {
                self.draggedCellIndexPath = draggedCellIndexPath as NSIndexPath
                let should = draggingDelegate?.dragDropCollectionViewShouldDraggingBeginWithCellAt?(indexPath: draggedCellIndexPath as NSIndexPath)
                if ((should != nil) && should!) || (should == nil) {
                    let draggedCell = cellForItem(at: draggedCellIndexPath) as UICollectionViewCell!
                    DispatchQueue.global(qos: .userInteractive).async {
                        self.draggingView = UIImageView(image: self.getRasterizedImageCopyOfCell(cell: draggedCell!))
                        DispatchQueue.main.async {
                            self.draggingView!.center = (draggedCell!.center)
                            self.addSubview(self.draggingView!)
                            draggedCell!.alpha = 0.0
                            self.touchOffsetFromCenterOfCell = CGPoint(x: draggedCell!.center.x - touchLocation.x, y: draggedCell!.center.y - touchLocation.y)
                            UIView.animate(withDuration: 0.4, animations: { () -> Void in
                                self.draggingView!.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
                                self.draggingView!.alpha = 0.8
                            })
                        }
                    }
                    
                } else {
                    self.draggedCellIndexPath = nil
                }
            }
            break
        case UIGestureRecognizerState.changed:
            if draggedCellIndexPath != nil && draggingView != nil {
                draggingView!.center = CGPoint(x: touchLocation.x + touchOffsetFromCenterOfCell!.x, y: touchLocation.y + touchOffsetFromCenterOfCell!.y)
                
                if !isAutoScrolling {
                    
                    dispatchOnMainQueueAfter(delay: pingInterval, closure: { () -> () in
                        let scroller = self.shouldAutoScroll(previousTouchLocation: touchLocation)
                        if  (scroller.shouldScroll) {
                            self.autoScroll(direction: scroller.direction)
                            self.isAutoScrolling = true
                        }
                    })
                }
                
                dispatchOnMainQueueAfter(delay: pingInterval, closure: { () -> () in
                    let shouldSwapCellsTuple = self.shouldSwapCells(previousTouchLocation: touchLocation)
                    if shouldSwapCellsTuple.shouldSwap {
                        self.swapDraggedCellWithCellAtIndexPath(newIndexPath: shouldSwapCellsTuple.newIndexPath!)
                    }
                })
            }
            break
        case UIGestureRecognizerState.ended:
            if draggedCellIndexPath != nil && draggingView != nil {
                let draggedCell = self.cellForItem(at: draggedCellIndexPath! as IndexPath)
                UIView.animate(withDuration: 0.4, animations: { () -> Void in
                    self.draggingView!.transform = CGAffineTransform.identity
                    self.draggingView!.alpha = 1.0
                    if (draggedCell != nil) {
                        self.draggingView!.center = draggedCell!.center
                    }
                }, completion: { (finished) -> Void in
                    self.draggingView!.removeFromSuperview()
                    self.draggingView = nil
                    draggedCell?.alpha = 1.0
                    self.draggingDelegate?.dragDropCollectionViewDraggingDidEndForCellAtIndexPath?(indexPath: self.draggedCellIndexPath!)
                    self.draggedCellIndexPath = nil
                })
            }
            break
        default:
            break
        }
    }
    
    
    func setDragging(enabled: Bool) {
        if enabled {
            longPressRecognizer.isEnabled = true
        } else {
            longPressRecognizer.isEnabled = false
        }
    }
    
    private func shouldSwapCells(previousTouchLocation: CGPoint) -> (shouldSwap: Bool, newIndexPath: NSIndexPath?) {
        var shouldSwap = false
        var newIndexPath: NSIndexPath?
        let currentTouchLocation = self.longPressRecognizer.location(in: self)
        if !Double(currentTouchLocation.x).isNaN && !Double(currentTouchLocation.y).isNaN {
            if distanceBetweenPoints(firstPoint: previousTouchLocation, secondPoint: currentTouchLocation) < CGFloat(20.0) {
                if let newIndexPathForCell = self.indexPathForItem(at: currentTouchLocation) {
                    if newIndexPathForCell != self.draggedCellIndexPath! as IndexPath {
                        shouldSwap = true
                        newIndexPath = draggingDelegate?.dragDropCollectionViewApprovedTargetIndexPath(newIndexPathForCell as NSIndexPath)
                    }
                }
            }
        }
        return (shouldSwap, newIndexPath)
    }
    
    private func swapDraggedCellWithCellAtIndexPath(newIndexPath: NSIndexPath) {
        self.moveItem(at: self.draggedCellIndexPath! as IndexPath, to: newIndexPath as IndexPath)
        let draggedCell = self.cellForItem(at: newIndexPath as IndexPath)!
        draggedCell.alpha = 0
        self.draggingDelegate?.dragDropCollectionViewDidMoveCellFrom(initialIndexPath: self.draggedCellIndexPath!, to: newIndexPath)
        self.draggedCellIndexPath = newIndexPath
    }
    
    
}

//AutoScroll
public extension DragDropCollectionView {
    enum AutoScrollDirection: Int {
        case Invalid = 0
        case TowardsOrigin = 1
        case AwayFromOrigin = 2
    }
    
    func autoScroll(direction: AutoScrollDirection) {
        let currentLongPressTouchLocation = self.longPressRecognizer.location(in: self)
        var increment: CGFloat
        var newContentOffset: CGPoint
        if (direction == AutoScrollDirection.TowardsOrigin) {
            increment = -50.0
        } else {
            increment = 50.0
        }
        newContentOffset = CGPoint(x: self.contentOffset.x, y: self.contentOffset.y + increment)
        if ((direction == AutoScrollDirection.TowardsOrigin && newContentOffset.y < 0) || (direction == AutoScrollDirection.AwayFromOrigin && newContentOffset.y > self.contentSize.height - self.frame.height)) {
            dispatchOnMainQueueAfter(delay: 0.3, closure: { () -> () in
                self.isAutoScrolling = false
            })
        } else {
            UIView.animate(withDuration: 0.3
                , delay: 0.0
                , options: UIViewAnimationOptions.curveLinear
                , animations: { () -> Void in
                    self.setContentOffset(newContentOffset, animated: false)
                    if (self.draggingView != nil) {
                        var draggingFrame = self.draggingView!.frame
                        draggingFrame.origin.y += increment
                        self.draggingView!.frame = draggingFrame
                    }
            }) { (finished) -> Void in
                dispatchOnMainQueueAfter(delay: 0.0, closure: { () -> () in
                    let updatedTouchLocationWithNewOffset = CGPoint(x: currentLongPressTouchLocation.x, y: currentLongPressTouchLocation.y + increment)
                    let scroller = self.shouldAutoScroll(previousTouchLocation: updatedTouchLocationWithNewOffset)
                    if scroller.shouldScroll {
                        self.autoScroll(direction: scroller.direction)
                    } else {
                        self.isAutoScrolling = false
                    }
                })
            }
        }
    }
    
    func shouldAutoScroll(previousTouchLocation: CGPoint) -> (shouldScroll: Bool, direction: AutoScrollDirection) {
        let previousTouchLocation = self.convert(previousTouchLocation, to: self.superview)
        let currentTouchLocation = self.longPressRecognizer.location(in: self.superview)
        
        if let flowLayout = self.collectionViewLayout as? UICollectionViewFlowLayout {
            if !Double(currentTouchLocation.x).isNaN && !Double(currentTouchLocation.y).isNaN {
                if distanceBetweenPoints(firstPoint: previousTouchLocation, secondPoint: currentTouchLocation) < CGFloat(20.0) {
                    let scrollDirection = flowLayout.scrollDirection
                    var scrollBoundsSize: CGSize
                    let scrollBoundsLength: CGFloat = 50.0
                    var scrollRectAtEnd: CGRect
                    switch scrollDirection {
                    case UICollectionViewScrollDirection.horizontal:
                        scrollBoundsSize = CGSize(width: scrollBoundsLength, height: self.frame.height)
                        scrollRectAtEnd = CGRect(x: self.frame.origin.x + self.frame.width - scrollBoundsSize.width , y: self.frame.origin.y, width: scrollBoundsSize.width, height: self.frame.height)
                        break
                    case UICollectionViewScrollDirection.vertical:
                        scrollBoundsSize = CGSize(width: self.frame.width, height: scrollBoundsLength)
                        scrollRectAtEnd = CGRect(x: self.frame.origin.x, y: self.frame.origin.y + self.frame.height - scrollBoundsSize.height, width: self.frame.width, height: scrollBoundsSize.height)
                        break
                    }
                    let scrollRectAtOrigin = CGRect(origin: self.frame.origin, size: scrollBoundsSize)
                    if scrollRectAtOrigin.contains(currentTouchLocation) {
                        return (true, AutoScrollDirection.TowardsOrigin)
                    } else if scrollRectAtEnd.contains(currentTouchLocation) {
                        return (true, AutoScrollDirection.AwayFromOrigin)
                    }
                }
            }
        }
        return (false, AutoScrollDirection.Invalid)
    }
}

// MARK: - Wiggle Animation
public extension DragDropCollectionView {
    func startWiggle() {
        for cell in visibleCells {
            addWiggleAnimationTo(cell: cell )
        }
        isWiggling = true
    }
    
    func stopWiggle() {
        for cell in visibleCells {
            cell.layer.removeAllAnimations()
        }
        isWiggling = false
    }
    
    override func dequeueReusableCell(withReuseIdentifier identifier: String, for indexPath: IndexPath) -> UICollectionViewCell {
        let cell: AnyObject = super.dequeueReusableCell(withReuseIdentifier: identifier, for: indexPath as IndexPath)
        if isWiggling {
            addWiggleAnimationTo(cell: cell as! UICollectionViewCell)
        } else {
            cell.layer.removeAllAnimations()
        }
        return cell as! UICollectionViewCell
    }
    
    func addWiggleAnimationTo(cell: UICollectionViewCell) {
        if isNotExcluded(excludedFromWiggle, cell: cell) {
            CATransaction.begin()
            CATransaction.setDisableActions(false)
            cell.layer.add(rotationAnimation(), forKey: "rotation")
            cell.layer.add(bounceAnimation(), forKey: "bounce")
            CATransaction.commit()
        }
    }
    
    private func rotationAnimation() -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        let angle = CGFloat(0.04)
        let duration = TimeInterval(0.1)
        let variance = Double(0.025)
        animation.values = [angle, -angle]
        animation.autoreverses = true
        animation.duration = self.randomize(interval: duration, withVariance: variance)
        animation.repeatCount = Float.infinity
        return animation
    }
    
    private func bounceAnimation() -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.y")
        let bounce = CGFloat(2.0)
        let duration = TimeInterval(0.12)
        let variance = Double(0.025)
        animation.values = [bounce, -bounce]
        animation.autoreverses = true
        animation.duration = self.randomize(interval: duration, withVariance: variance)
        animation.repeatCount = Float.infinity
        return animation
    }
    
    private func randomize(interval: TimeInterval, withVariance variance:Double) -> TimeInterval {
        let random = (Double(arc4random_uniform(1000)) - 500.0) / 500.0
        return interval + variance * random;
    }
}

//Assisting Functions
public extension DragDropCollectionView {
    func getRasterizedImageCopyOfCell(cell: UICollectionViewCell) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(cell.bounds.size, false, 0.0)
        cell.layer.render(in: UIGraphicsGetCurrentContext()!)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image!
    }
    
}

public func dispatchOnMainQueueAfter(delay:Double, closure:@escaping ()->Void) {
    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now()+delay, qos: DispatchQoS.userInteractive, flags: DispatchWorkItemFlags.enforceQoS, execute: closure)
}

public func distanceBetweenPoints(firstPoint: CGPoint, secondPoint: CGPoint) -> CGFloat {
    let xDistance = firstPoint.x - secondPoint.x
    let yDistance = firstPoint.y - secondPoint.y
    return sqrt(xDistance * xDistance + yDistance * yDistance)
}
