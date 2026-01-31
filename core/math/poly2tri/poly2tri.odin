//https://github.com/jhasse/poly2tri
package poly2tri

import "core:math"
import "core:slice"
import "core:mem"
import "core:debug/trace"
import "core:math/linalg"
import "base:runtime"
import "base:intrinsics"


Trianguate_Error :: enum {
    None,

    Edge_P1_Equal_P2,
    Triangle_MarkNeighbor2_target_not_a_neighbor,
    Triangle_PointCW_point_not_in_triangle,
    Triangle_PointCCW_point_not_in_triangle,
    Triangle_Index_point_not_in_triangle,
    Triangle_Legalize_opoint_not_in_triangle,
    AdvancingFront_LocatePoint_point_not_found,
    EdgeEvent2_nil_triangle,
    EdgeEvent2_collinear_points_not_supported,
    FlipEdgeEvent_nil_triangle,
    FlipEdgeEvent_nil_neighbor_across,
    Opposing_point_on_constrained_edge,//!Unsupported
    FlipScanEdgeEvent_nil_neighbor_across,
    FlipScanEdgeEvent_nil_opposing_point,
    FlipScanEdgeEvent_nil_on_either_of_points,
    FlipEdgeEvent_nil_Triangle,
    FlipEdgeEvent_nil_Neighbor_Across,

    nil_node,
}


@(private = "file") kAlpha : f32 : 0.3
@(private = "file") Triangle :: struct {
    pts: [3]^PointE,
    neighbors: [3]^Triangle,
    constrainedEdge: [3]bool,
    delaunayEdge: [3]bool,
    interior: bool,
}

//AdvancingFrontNode
@(private = "file") Node :: struct {
    point: ^PointE,
    triangle: ^Triangle,
    next, prev: ^Node,
    value: f32,
}

@(private = "file") Edge :: struct {
    p,q: ^PointE,
}

@(private = "file") EdgeEvent_ :: struct {
    constrainedEdge: ^Edge,
    right:bool,
}

@(private = "file") AdvancingFront :: struct {
    head, tail, search: ^Node,
}

@(private = "file") PointE :: struct {
    using _: linalg.point,
    edges:[dynamic]^Edge,
    id: u32,
}

@(private = "file") Node_Init :: proc {
    Node_InitPts,
    Node_InitPtsTriangle,
}

@(private = "file") Node_InitPts :: proc "contextless" (point: ^PointE) -> Node {
    return Node{point = point, value = point.x}
}

@(private = "file") Node_InitPtsTriangle :: proc "contextless" (point: ^PointE, triangle: ^Triangle) -> Node {
    return Node{point = point, triangle = triangle, value = point.x}
}

@(private = "file") AdvancingFront_LocateNode :: proc "contextless" (self: ^AdvancingFront, x: f32) -> ^Node {
    node := self.search

    if x < node.value {
        for node = node.prev;node != nil;node = node.prev {
            if x >= node.value {
                self.search = node
                return node
            }
        }
    } else {
        for node = node.next;node != nil;node = node.next {
            if x < node.value {
                self.search = node.prev
                return node.prev
            }
        }
    }
    return nil
}

@(private = "file") AdvancingFront_Init :: proc "contextless" (head, tail: ^Node) -> AdvancingFront {
    return AdvancingFront{head = head, tail = tail, search = head}
}

@(private = "file") PointE_Init :: proc(point: linalg.point, id:u32) -> PointE {
    return PointE{x = point.x, y = point.y, id = id, edges = mem.make_non_zeroed_dynamic_array([dynamic]^Edge, context.temp_allocator)}
}


@(require_results, private = "file") Edge_Init :: proc(p1, p2: ^PointE, out:^Edge) -> (err:Trianguate_Error = .None) {
    p: ^PointE = p1
    q: ^PointE = p2
    if (p1.y > p2.y) {
        q = p1
        p = p2
    } else if (p1.y == p2.y) {
        if (p1.x > p2.x) {
            q = p1
            p = p2
        } else if (p1.x == p2.x) {
            err = .Edge_P1_Equal_P2
            return
        }
    } 
    non_zero_append(&q.edges, out)
    out^ = Edge{p = p, q = q}

    return
}

@(private = "file") Triangle_MarkNeighbor2 :: proc "contextless"(self, target: ^Triangle, p1, p2: ^PointE) -> (err:Trianguate_Error = .None) {
    if (p1 == self.pts[2] && p2 == self.pts[1]) || (p1 == self.pts[1] && p2 == self.pts[2]) {
        self.neighbors[0] = target
    } else if (p1 == self.pts[0] && p2 == self.pts[2]) || (p1 == self.pts[2] && p2 == self.pts[0]) {
        self.neighbors[1] = target
    } else if (p1 == self.pts[0] && p2 == self.pts[1]) || (p1 == self.pts[1] && p2 == self.pts[0]) {
        self.neighbors[2] = target
    } else {
        err = .Triangle_MarkNeighbor2_target_not_a_neighbor
        return
    }
    return
}

@(private = "file") Triangle_MarkNeighbor :: proc "contextless" (self, target: ^Triangle) -> (err:Trianguate_Error = .None) {
    if Triangle_Contains2(target, self.pts[1], self.pts[2]) {
        self.neighbors[0] = target
        Triangle_MarkNeighbor2(target, self, self.pts[1], self.pts[2]) or_return
    } else if Triangle_Contains2(target, self.pts[0], self.pts[2]) {
        self.neighbors[1] = target
        Triangle_MarkNeighbor2(target, self, self.pts[0], self.pts[2]) or_return
    } else if Triangle_Contains2(target, self.pts[0], self.pts[1]) {
        self.neighbors[2] = target
        Triangle_MarkNeighbor2(target, self, self.pts[0], self.pts[1]) or_return
    }
    return
}

@(private = "file") Triangle_MarkConstrainedEdge :: proc "contextless" (self: ^Triangle, p, q: ^PointE) {
    if (q == self.pts[0] && p == self.pts[1]) || (q == self.pts[1] && p == self.pts[0]) {
        self.constrainedEdge[2] = true;
    } else if (q == self.pts[0] && p == self.pts[2]) || (q == self.pts[2] && p == self.pts[0]) {
        self.constrainedEdge[1] = true;
    } else if (q == self.pts[1] && p == self.pts[2]) || (q == self.pts[2] && p == self.pts[1]) {
        self.constrainedEdge[0] = true;
    }
}

@(private = "file") Triangle_MarkConstrainedEdge2 :: #force_inline proc "contextless" (self: ^Triangle, e: ^Edge) {
    Triangle_MarkConstrainedEdge(self, e.p, e.q)
}

@(private = "file") Triangle_Contains :: #force_inline proc "contextless" (self: ^Triangle, p: ^PointE) -> bool {
    return self.pts[0] == p || self.pts[1] == p || self.pts[2] == p
}

@(private = "file") Triangle_Contains2 :: #force_inline proc "contextless" (self: ^Triangle, p: ^PointE, q: ^PointE) -> bool {
    return Triangle_Contains(self, p) && Triangle_Contains(self, q)
}

@(require_results, private = "file") Triangle_PointCW :: proc "contextless" (self: ^Triangle, p: ^PointE) -> (^PointE, Trianguate_Error) {
    if self.pts[0] == p do return self.pts[2], .None
    else if self.pts[1] == p do return self.pts[0], .None
    else if self.pts[2] == p do return self.pts[1], .None
    
    return nil, .Triangle_PointCW_point_not_in_triangle
}

@(require_results, private = "file") Triangle_PointCCW :: proc "contextless" (self: ^Triangle, p: ^PointE) ->(^PointE, Trianguate_Error) {
    if self.pts[0] == p do return self.pts[1], .None
    else if self.pts[1] == p do return self.pts[2], .None
    else if self.pts[2] == p do return self.pts[0], .None
    
     return nil, .Triangle_PointCCW_point_not_in_triangle
}

@(private = "file") Triangle_NeighborCW :: proc "contextless" (self: ^Triangle, p: ^PointE) -> ^Triangle {
    if self.pts[0] == p do return self.neighbors[1]
    else if self.pts[1] == p do return self.neighbors[2]
    return self.neighbors[0]
}
@(private = "file") Triangle_NeighborCCW :: proc "contextless" (self: ^Triangle, p: ^PointE) -> ^Triangle {
    if self.pts[0] == p do return self.neighbors[2]
    else if self.pts[1] == p do return self.neighbors[0]
    return self.neighbors[1]
}
@(private = "file") Triangle_NeighborAcross :: proc "contextless" (self: ^Triangle, p: ^PointE) -> ^Triangle {
    if self.pts[0] == p do return self.neighbors[0]
    else if self.pts[1] == p do return self.neighbors[1]
    return self.neighbors[2]
}

@(private = "file") Triangle_GetConstrainedEdgeCCW :: proc "contextless" (self: ^Triangle, p: ^PointE) -> bool {
    if p == self.pts[0] {
        return self.constrainedEdge[2]
    } else if p == self.pts[1] {
        return self.constrainedEdge[0]
    }
    return self.constrainedEdge[1]
}

@(private = "file") Triangle_GetConstrainedEdgeCW :: proc "contextless" (self: ^Triangle, p: ^PointE) -> bool {
    if p == self.pts[0] {
        return self.constrainedEdge[1]
    } else if p == self.pts[1] {
        return self.constrainedEdge[2]
    }
    return self.constrainedEdge[0]
}

@(private = "file") Triangle_SetConstrainedEdgeCCW :: proc "contextless" (self: ^Triangle, p: ^PointE, ce: bool) {
    if p == self.pts[0] {
        self.constrainedEdge[2] = ce
    } else if p == self.pts[1] {
        self.constrainedEdge[0] = ce
    } else {
        self.constrainedEdge[1] = ce
    }
}

@(private = "file") Triangle_SetConstrainedEdgeCW :: proc "contextless" (self: ^Triangle, p: ^PointE, ce: bool) {
    if p == self.pts[0] {
        self.constrainedEdge[1] = ce
    } else if p == self.pts[1] {
        self.constrainedEdge[2] = ce
    } else {
        self.constrainedEdge[0] = ce
    }
}

@(private = "file") Triangle_GetDelaunayEdgeCCW :: proc "contextless" (self: ^Triangle, p: ^PointE) -> bool {
    if p == self.pts[0] {
        return self.delaunayEdge[2]
    } else if p == self.pts[1] {
        return self.delaunayEdge[0]
    }
    return self.delaunayEdge[1]
}

@(private = "file") Triangle_GetDelaunayEdgeCW :: proc "contextless" (self: ^Triangle, p: ^PointE) -> bool {
    if p == self.pts[0] {
        return self.delaunayEdge[1]
    } else if p == self.pts[1] {
        return self.delaunayEdge[2]
    }
    return self.delaunayEdge[0]
}

@(private = "file") Triangle_SetDelaunayEdgeCCW :: proc "contextless" (self: ^Triangle, p: ^PointE, e: bool) {
    if p == self.pts[0] {
        self.delaunayEdge[2] = e
    } else if p == self.pts[1] {
        self.delaunayEdge[0] = e
    } else {
        self.delaunayEdge[1] = e
    }
}

@(private = "file") Triangle_SetDelaunayEdgeCW :: proc "contextless" (self: ^Triangle, p: ^PointE, e: bool) {
    if p == self.pts[0] {
        self.delaunayEdge[1] = e
    } else if p == self.pts[1] {
        self.delaunayEdge[2] = e
    } else {
        self.delaunayEdge[0] = e
    }
}

@(require_results, private = "file") Triangle_OppositePoint :: #force_inline proc "contextless" (self, t: ^Triangle, p: ^PointE) -> (res:^PointE, err:Trianguate_Error) {
    cw := Triangle_PointCW(t, p) or_return
    res = Triangle_PointCW(self, cw) or_return
    return 
}

@(require_results, private = "file") Triangle_Index :: #force_inline proc "contextless" (self: ^Triangle, p: ^PointE) -> (int, Trianguate_Error) {
    if self.pts[0] == p do return 0, .None
    else if self.pts[1] == p do return 1, .None
    else if self.pts[2] == p do return 2, .None
    
    return -1, .Triangle_Index_point_not_in_triangle
}

@(private = "file") Basin :: struct {
    left_node: ^Node,
    right_node: ^Node,
    bottom_node: ^Node,
    width: f32,
    left_highest: bool,
}

@(private = "file") TriangleCtx :: struct {
    maps: [dynamic]^Triangle,
    edges: []Edge,
    nodes: []Node,
    pts: []^PointE,
    ptsData: []PointE,
    indices: [dynamic]u32,
    allocator: runtime.Allocator,

    xmax, xmin, ymax, ymin: f32,
    front: AdvancingFront,
    edgeEvents: EdgeEvent_,
    basin: Basin,
}

@(private = "file") InCircle :: proc "contextless" (pa, pb, pc, pd: ^PointE) -> bool {
    adx := pa.x - pd.x
    ady := pa.y - pd.y
    bdx := pb.x - pd.x
    bdy := pb.y - pd.y

    adxbdy := adx * bdy
    bdxady := bdx * ady
    oabd := adxbdy - bdxady

    if oabd <= 0 do return false

    cdx := pc.x - pd.x
    cdy := pc.y - pd.y

    cdxady := cdx * ady
    adxcdy := adx * cdy
    ocad := cdxady - adxcdy

    if ocad <= 0 do return false

    bdxcdy := bdx * cdy
    cdxbdy := cdx * bdy

    alift := adx * adx + ady * ady
    blift := bdx * bdx + bdy * bdy
    clift := cdx * cdx + cdy * cdy

    det := alift * (bdxcdy - cdxbdy) + blift * ocad + clift * oabd

    return det > 0
}

@(private = "file") Triangle_Legalize :: proc "contextless" (t: ^Triangle, opoint, npoint: ^PointE) -> (err:Trianguate_Error = .None) {
    if opoint == t.pts[0] {
        t.pts[1] = t.pts[0]
        t.pts[0] = t.pts[2]
        t.pts[2] = npoint
    } else if opoint == t.pts[1] {
        t.pts[2] = t.pts[1]
        t.pts[1] = t.pts[0]
        t.pts[0] = npoint
    } else if opoint == t.pts[2] {
        t.pts[0] = t.pts[2]
        t.pts[2] = t.pts[1]
        t.pts[1] = npoint
    } else {
        err = .Triangle_Legalize_opoint_not_in_triangle
        return
    }
    return
}

@(private = "file") Triangle_ClearNeighbors :: proc "contextless" (t: ^Triangle) {
    t.neighbors[0] = nil
    t.neighbors[1] = nil
    t.neighbors[2] = nil
}

@(private = "file") RotateTrianglePair :: proc "contextless" (t: ^Triangle, p: ^PointE, ot: ^Triangle, op: ^PointE) -> (res:bool, err:Trianguate_Error = .None) {
    n1, n2, n3, n4: ^Triangle

    n1 = Triangle_NeighborCCW(t, p)
    n2 = Triangle_NeighborCW(t, p)
    n3 = Triangle_NeighborCCW(ot, op)
    n4 = Triangle_NeighborCW(ot, op)
    
    ce1 := Triangle_GetConstrainedEdgeCCW(t, p)
    ce2 := Triangle_GetConstrainedEdgeCW(t, p)
    ce3 := Triangle_GetConstrainedEdgeCCW(ot, op)
    ce4 := Triangle_GetConstrainedEdgeCW(ot, op)
    
    de1 := Triangle_GetDelaunayEdgeCCW(t, p)
    de2 := Triangle_GetDelaunayEdgeCW(t, p)
    de3 := Triangle_GetDelaunayEdgeCCW(ot, op)
    de4 := Triangle_GetDelaunayEdgeCW(ot, op)
    
    Triangle_Legalize(t, p, op) or_return
    Triangle_Legalize(ot, op, p) or_return

    Triangle_SetDelaunayEdgeCCW(ot, p, de1)
    Triangle_SetDelaunayEdgeCW(t, p, de2)
    Triangle_SetDelaunayEdgeCCW(t, op, de3)
    Triangle_SetDelaunayEdgeCW(ot, op, de4)

    Triangle_SetConstrainedEdgeCCW(ot, p, ce1)
    Triangle_SetConstrainedEdgeCW(t, p, ce2)
    Triangle_SetConstrainedEdgeCCW(t, op, ce3)
    Triangle_SetConstrainedEdgeCW(ot, op, ce4)
    
    Triangle_ClearNeighbors(t)
    Triangle_ClearNeighbors(ot)
    if n1 != nil do Triangle_MarkNeighbor(ot, n1) or_return
    if n2 != nil do Triangle_MarkNeighbor(t, n2) or_return
    if n3 != nil do Triangle_MarkNeighbor(t, n3) or_return
    if n4 != nil do Triangle_MarkNeighbor(ot, n4) or_return
    Triangle_MarkNeighbor(t, ot) or_return
    
    return true, .None
}

@(private = "file") AdvancingFront_FindSearchNode :: proc "contextless" (front: ^AdvancingFront, x: f32) -> ^Node {
    _ = x
    // TODO: implement BST index
    return front.search
}

@(private = "file") AdvancingFront_LocatePoint :: proc "contextless" (front: ^AdvancingFront, point: ^PointE) -> (res:^Node, err:Trianguate_Error = .None) {
    px := point.x
    node := AdvancingFront_FindSearchNode(front, px)
    nx := node.point.x

    if px == nx {
        if point != node.point {
            if point == node.prev.point {
                node = node.prev
            } else if point == node.next.point {
                node = node.next
            } else {
                err = .AdvancingFront_LocatePoint_point_not_found
                return
            }
        }
    } else if px < nx {
        for {
            node = node.prev
            if node == nil do break
            if point == node.point do break
        }
    } else {
        for {
            node = node.next
            if node == nil do break
            if point == node.point do break
        }
    }
    
    if node != nil do front.search = node
    
    res = node
    return
}

@(require_results, private = "file") MapTriangleToNodes :: proc "contextless" (ctx: ^TriangleCtx, t: ^Triangle) -> (err:Trianguate_Error = .None) {
    for i in 0..<3 {
        if t.neighbors[i] == nil {
            n := AdvancingFront_LocatePoint(&ctx.front, Triangle_PointCW(t, t.pts[i]) or_return) or_return
            if n != nil {
                n.triangle = t
            }
        }
    }
    return
}

@(private = "file") Legalize :: proc "contextless" (ctx: ^TriangleCtx, t: ^Triangle) -> (res : bool, err : Trianguate_Error = .None) {
    for i in 0..<3 {
        if t.delaunayEdge[i] {
            continue
        }

        ot := t.neighbors[i]
        if ot != nil {
            p := t.pts[i]
            op := Triangle_OppositePoint(ot, t, p) or_return
            oi := Triangle_Index(ot, op) or_return

            if ot.constrainedEdge[oi] || ot.delaunayEdge[oi] {
                t.constrainedEdge[i] = ot.constrainedEdge[oi]
                continue
            }

            tcw := Triangle_PointCW(t, p) or_return
            tccw := Triangle_PointCCW(t, p) or_return
            inside := InCircle(p, tccw, tcw, op)

            if inside {
                t.delaunayEdge[i] = true
                ot.delaunayEdge[oi] = true

                RotateTrianglePair(t, p, ot, op) or_return

                notLegalized := Legalize(ctx, t) or_return
                notLegalized = !notLegalized
                if notLegalized {
                    MapTriangleToNodes(ctx, t) or_return
                }

                notLegalized = Legalize(ctx, ot) or_return
                notLegalized = !notLegalized
                if notLegalized {
                    MapTriangleToNodes(ctx, ot) or_return
                }

                t.delaunayEdge[i] = false
                ot.delaunayEdge[oi] = false

                res = true
                return
            }  
        }
    }
    res = false
    return
}

@(private = "file") Triangle_EdgeIndex :: proc "contextless" (self: ^Triangle, p1, p2: ^PointE) -> int {
    if self.pts[0] == p1 {
        if self.pts[1] == p2 {
            return 2
        } else if self.pts[2] == p2 {
            return 1
        }
    } else if self.pts[1] == p1 {
        if self.pts[2] == p2 {
            return 0
        } else if self.pts[0] == p2 {
            return 2
        }
    } else if self.pts[2] == p1 {
        if self.pts[0] == p2 {
            return 1
        } else if self.pts[1] == p2 {
            return 0
        }
    }
    return -1
}

@(private = "file") IsEdgeSideOfTriangle :: proc "contextless" (t: ^Triangle, ep, eq: ^PointE) -> bool {
    index := Triangle_EdgeIndex(t, ep, eq)
    if index != -1 {
        t.constrainedEdge[index] = true
        t_ := t.neighbors[index]
        if t_ != nil {
            Triangle_MarkConstrainedEdge(t_, ep, eq)
        }
        return true
    }
    return false
}

@(private = "file") FillEdgeEvent :: proc (ctx: ^TriangleCtx, e: ^Edge, node: ^Node) {
    if ctx.edgeEvents.right {
        FillRightAboveEdgeEvent(ctx, e, node)
    } else {
        FillLeftAboveEdgeEvent(ctx, e, node)
    }
}

@(private = "file") FillRightAboveEdgeEvent :: proc (ctx: ^TriangleCtx, edge: ^Edge, node: ^Node) {
    node_ := node
    for node_.next.point.x < edge.p.x {
        if Orient2d(edge.q, node_.next.point, edge.p) == .CCW {
            FillRightBelowEdgeEvent(ctx, edge, node_)
        } else {
            node_ = node_.next
        }
    }
}

@(private = "file") FillRightBelowEdgeEvent :: proc (ctx: ^TriangleCtx, edge: ^Edge, node: ^Node) {
    if node.point.x < edge.p.x {
        if Orient2d(node.point, node.next.point, node.next.next.point) == .CCW {
            FillRightConcaveEdgeEvent(ctx, edge, node)
        } else {
            FillRightConvexEdgeEvent(ctx, edge, node)
            FillRightBelowEdgeEvent(ctx, edge, node)
        }
    }
}

@(private = "file") FillRightConcaveEdgeEvent :: proc (ctx: ^TriangleCtx, edge: ^Edge, node: ^Node) {
    Fill(ctx, node.next)
    if node.next.point != edge.p {
        if Orient2d(edge.q, node.next.point, edge.p) == .CCW {
            if Orient2d(node.point, node.next.point, node.next.next.point) == .CCW {
                FillRightConcaveEdgeEvent(ctx, edge, node)
            } else {
            }
        }
    }
}

@(private = "file") FillRightConvexEdgeEvent :: proc (ctx: ^TriangleCtx, edge: ^Edge, node: ^Node) {
    if Orient2d(node.next.point, node.next.next.point, node.next.next.next.point) == .CCW {
        FillRightConcaveEdgeEvent(ctx, edge, node.next)
    } else {
        if Orient2d(edge.q, node.next.next.point, edge.p) == .CCW {
            FillRightConvexEdgeEvent(ctx, edge, node.next)
        } else {
        }
    }
}

@(private = "file") FillLeftAboveEdgeEvent :: proc (ctx: ^TriangleCtx, edge: ^Edge, node: ^Node) {
    node_ := node
    for node_.prev.point.x > edge.p.x {
        if Orient2d(edge.q, node_.prev.point, edge.p) == .CW {
            FillLeftBelowEdgeEvent(ctx, edge, node_)
        } else {
            node_ = node_.prev
        }
    }
}

@(private = "file") FillLeftBelowEdgeEvent :: proc (ctx: ^TriangleCtx, edge: ^Edge, node: ^Node) {
    if node.point.x > edge.p.x {
        if Orient2d(node.point, node.prev.point, node.prev.prev.point) == .CW {
            FillLeftConcaveEdgeEvent(ctx, edge, node)
        } else {
            FillLeftConvexEdgeEvent(ctx, edge, node)
            FillLeftBelowEdgeEvent(ctx, edge, node)
        }
    }
}

@(private = "file") FillLeftConvexEdgeEvent :: proc (ctx: ^TriangleCtx, edge: ^Edge, node: ^Node) {
    if Orient2d(node.prev.point, node.prev.prev.point, node.prev.prev.prev.point) == .CW {
        FillLeftConcaveEdgeEvent(ctx, edge, node.prev)
    } else {
        if Orient2d(edge.q, node.prev.prev.point, edge.p) == .CW {
            FillLeftConvexEdgeEvent(ctx, edge, node.prev)
        } else {
        }
    }
}

@(private = "file") FillLeftConcaveEdgeEvent :: proc (ctx: ^TriangleCtx, edge: ^Edge, node: ^Node) {
    Fill(ctx, node.prev)
    if node.prev.point != edge.p {
        if Orient2d(edge.q, node.prev.point, edge.p) == .CW {
            if Orient2d(node.point, node.prev.point, node.prev.prev.point) == .CW {
                FillLeftConcaveEdgeEvent(ctx, edge, node)
            } else {
            }
        }
    }
}

@(private = "file") Orientation :: enum { CW, CCW, COLLINEAR };

@(private = "file") Orient2d :: proc "contextless" (pa, pb, pc: ^PointE) -> Orientation {
    detleft := (pa.x - pc.x) * (pb.y - pc.y)
    detright := (pa.y - pc.y) * (pb.x - pc.x)
    val := detleft - detright

    if (val == 0) {
        return .COLLINEAR
    } else if (val > 0) {
        return .CCW
    }
    return .CW
}

@(require_results, private = "file") EdgeEvent :: proc (ctx: ^TriangleCtx, e: ^Edge, node: ^Node) -> (err:Trianguate_Error = .None) {
    ctx.edgeEvents.constrainedEdge = e
    ctx.edgeEvents.right = e.p.x > e.q.x

    if IsEdgeSideOfTriangle(node.triangle, e.p, e.q) do return
    
    FillEdgeEvent(ctx, e, node)
    EdgeEvent2(ctx, e.p, e.q, node.triangle, e.q) or_return
    return
}

@(require_results, private = "file") EdgeEvent2 :: proc "contextless" (ctx: ^TriangleCtx, ep, eq: ^PointE, triangle: ^Triangle, point: ^PointE) -> (err:Trianguate_Error = .None) {
    triangle_ := triangle
    if triangle_ == nil {
        err = .EdgeEvent2_nil_triangle
        return
    }
    
    if IsEdgeSideOfTriangle(triangle_, ep, eq) do return

    p1 := Triangle_PointCCW(triangle_, point) or_return
    o1 := Orient2d(eq, p1, ep)
    if o1 == .COLLINEAR {
        if Triangle_Contains2(triangle_, eq, p1) {
            Triangle_MarkConstrainedEdge(triangle_, eq, p1)
            ctx.edgeEvents.constrainedEdge.q = p1
            triangle_ = Triangle_NeighborAcross(triangle_, point)
            EdgeEvent2(ctx, ep, p1, triangle_, p1) or_return
        } else {
            err = .EdgeEvent2_collinear_points_not_supported
        }
        return
    }

    p2 := Triangle_PointCW(triangle_, point) or_return
    o2 := Orient2d(eq, p2, ep)
    if o2 == .COLLINEAR {
        if Triangle_Contains2(triangle_, eq, p2) {
            Triangle_MarkConstrainedEdge(triangle_, eq, p2)
            ctx.edgeEvents.constrainedEdge.q = p2
            triangle_ = Triangle_NeighborAcross(triangle_, point)
            EdgeEvent2(ctx, ep, p2, triangle_, p2) or_return
        } else {
             err = .EdgeEvent2_collinear_points_not_supported
        }
        return
    }

    if o1 == o2 {
        if o1 == .CW {
            triangle_ = Triangle_NeighborCCW(triangle_, point)
        } else {
            triangle_ = Triangle_NeighborCW(triangle_, point)
        }
        EdgeEvent2(ctx, ep, eq, triangle_, point) or_return
    } else {
        if triangle_ == nil {
            err = .EdgeEvent2_nil_triangle
        }
        FlipEdgeEvent(ctx, ep, eq, triangle_, point) or_return
    }
    return
}

@(private = "file") FlipEdgeEvent :: proc "contextless" (ctx: ^TriangleCtx, ep, eq: ^PointE, t: ^Triangle, p: ^PointE) -> (err:Trianguate_Error = .None) {
    t_ := t
    if t_ == nil {
        err = .FlipEdgeEvent_nil_triangle
        return
    }
    
    ot := Triangle_NeighborAcross(t_, p)
    if ot == nil {
        err = .FlipEdgeEvent_nil_Neighbor_Across
        return
    }
    
    op := Triangle_OppositePoint(ot, t_, p) or_return
  
    if InScanArea(p, Triangle_PointCCW(t_, p) or_return, Triangle_PointCW(t_, p) or_return, op) {
        RotateTrianglePair(t_, p, ot, op) or_return
        MapTriangleToNodes(ctx, t_) or_return
        MapTriangleToNodes(ctx, ot) or_return
  
        if p == eq && op == ep {
            if eq == ctx.edgeEvents.constrainedEdge.q && ep == ctx.edgeEvents.constrainedEdge.p {
                Triangle_MarkConstrainedEdge(t_, ep, eq)
                Triangle_MarkConstrainedEdge(ot, ep, eq)
                Legalize(ctx, t_) or_return
                Legalize(ctx, ot) or_return
            }
        } else {
            o := Orient2d(eq, op, ep)
            t_ = NextFlipTriangle(ctx, o, t_, ot, p, op)
            FlipEdgeEvent(ctx, ep, eq, t_, p)
        }
    } else {
        newP := NextFlipPoint(ep, eq, ot, op) or_return
        FlipScanEdgeEvent(ctx, ep, eq, t_, ot, newP) or_return
        EdgeEvent2(ctx, ep, eq, t_, p) or_return
    }
    return
}

@(private = "file") NextFlipTriangle :: proc "contextless" (ctx: ^TriangleCtx, o: Orientation, t: ^Triangle, ot: ^Triangle, p: ^PointE, op: ^PointE) -> ^Triangle {
    ot_ := ot
    t_ := t

    if o == .CCW {
        edge_index := Triangle_EdgeIndex(ot_, p, op)
        ot_.delaunayEdge[edge_index] = true
        Legalize(ctx, ot_)
        Triangle_ClearDelunayEdges(ot_)
        return t
    }

    edgeIndex := Triangle_EdgeIndex(t_, p, op)
    t_.delaunayEdge[edgeIndex] = true
    Legalize(ctx, t_)
    Triangle_ClearDelunayEdges(t_)
    return ot
}

@(private = "file") Triangle_ClearDelunayEdges :: proc "contextless" (t: ^Triangle) {
    for i in 0..<3 {
        t.delaunayEdge[i] = false
    }
}

@(require_results, private = "file") NextFlipPoint :: proc "contextless" (ep, eq: ^PointE, ot: ^Triangle, op: ^PointE) -> (res:^PointE, err:Trianguate_Error = .None) {
    o2d := Orient2d(eq, op, ep)
    if o2d == .CW {
        return Triangle_PointCCW(ot, op)
    } else if o2d == .CCW {
        return Triangle_PointCW(ot, op)
    }
    err = .Opposing_point_on_constrained_edge
    return
}

@(require_results, private = "file") FlipScanEdgeEvent :: proc "contextless" (ctx: ^TriangleCtx, ep, eq: ^PointE, flipTriangle, t: ^Triangle, p: ^PointE) -> (err:Trianguate_Error = .None) {
    ot_ptr := Triangle_NeighborAcross(t, p)
    if ot_ptr == nil {
        err = .FlipScanEdgeEvent_nil_neighbor_across
        return
    }

    op_ptr := Triangle_OppositePoint(ot_ptr, t, p) or_return
    if op_ptr == nil {
       err = .FlipScanEdgeEvent_nil_opposing_point
        return
    }

    p1 := Triangle_PointCCW(flipTriangle, eq) or_return
    p2 := Triangle_PointCW(flipTriangle, eq) or_return
    if p1 == nil || p2 == nil {
        err = .FlipScanEdgeEvent_nil_on_either_of_points
        return
    }

    ot := ot_ptr
    op := op_ptr

    if InScanArea(eq, p1, p2, op) {
        FlipEdgeEvent(ctx, eq, op, ot, op) or_return
    } else {
        newP := NextFlipPoint(ep, eq, ot, op) or_return
        FlipScanEdgeEvent(ctx, ep, eq, flipTriangle, ot, newP) or_return
    }
    return
}

@(private = "file") InScanArea :: proc "contextless" (pa,pb,pc,pd: ^PointE) -> bool {
    oadb := (pa.x - pb.x)*(pd.y - pb.y) - (pd.x - pb.x)*(pa.y - pb.y)
    if oadb >= -math.epsilon(f32) {
        return false
    }

    oadc := (pa.x - pc.x)*(pd.y - pc.y) - (pd.x - pc.x)*(pa.y - pc.y)
    if oadc <= math.epsilon(f32) {
        return false
    }
    return true
}

TrianguateSinglePolygon :: proc(poly:[]linalg.point, baseIdx:[]u32, holes:[][]linalg.point = nil, allocator := context.allocator) -> (indices:[]u32, err:Trianguate_Error = .None) {
    ctx := TriangleCtx{allocator = allocator}
   
    if holes == nil {
        ctx.pts = mem.make_non_zeroed([]^PointE, len(poly), 64, context.temp_allocator)
        ctx.ptsData = mem.make_non_zeroed([]PointE, len(poly), 64, context.temp_allocator)
        ctx.edges = mem.make_non_zeroed([]Edge, len(poly), 64, context.temp_allocator)
        ctx.nodes = mem.make_non_zeroed([]Node, len(poly) - 1, 64, context.temp_allocator)
    } else {
        holeLen := 0
        for hole in holes {
            holeLen += len(hole)
        }
        ctx.pts = mem.make_non_zeroed([]^PointE, len(poly) + holeLen, 64, context.temp_allocator)
        ctx.ptsData = mem.make_non_zeroed([]PointE, len(poly) + holeLen, 64, context.temp_allocator)
        ctx.edges = mem.make_non_zeroed([]Edge, len(poly) + holeLen, 64, context.temp_allocator)
        ctx.nodes = mem.make_non_zeroed([]Node, len(poly) + holeLen - 1, 64, context.temp_allocator)
    }
    ctx.indices = mem.make_non_zeroed_dynamic_array([dynamic]u32, allocator)
    ctx.maps = mem.make_non_zeroed_dynamic_array([dynamic]^Triangle, context.temp_allocator)
  
    ctx.allocator = allocator

    defer {
        for t in ctx.maps {
            free(t, context.temp_allocator)
        }
        delete(ctx.maps)
        delete(ctx.edges, context.temp_allocator)
        delete(ctx.nodes, context.temp_allocator)
        for p in ctx.pts {
            delete(p.edges)
        }
        delete(ctx.pts, context.temp_allocator)
        delete(ctx.ptsData, context.temp_allocator)
    }
    _baseIdx := 0

    for p, i in poly {
        ctx.ptsData[i] = PointE_Init(p, u32(i) + baseIdx[_baseIdx])
        ctx.pts[i] = &ctx.ptsData[i] 
    }
    _baseIdx += 1

    for _, i in poly {
        j := i < len(poly) - 1 ? i + 1 : 0
        Edge_Init(ctx.pts[i], ctx.pts[j], &ctx.edges[i]) or_return
    }

    if holes != nil {
        idx := len(poly)
        for hole in holes {
            for p, i in hole {
                ctx.ptsData[idx + i] = PointE_Init(p, u32(i) + baseIdx[_baseIdx])
                ctx.pts[idx + i] = &ctx.ptsData[idx + i]
            }
            _baseIdx += 1
        
            for _, i in hole {
                j := i < len(hole) - 1 ? i + 1 : 0
                Edge_Init(ctx.pts[i + idx], ctx.pts[j + idx], &ctx.edges[i + idx]) or_return
            }

            idx += len(hole)
        }
    }

    ctx.xmax = ctx.pts[0].x
    ctx.xmin = ctx.pts[0].x
    ctx.ymax = ctx.pts[0].y
    ctx.ymin = ctx.pts[0].y

    for p in ctx.pts[:] {
        if p.x > ctx.xmax { ctx.xmax = p.x }
        if p.x < ctx.xmin { ctx.xmin = p.x }
        if p.y > ctx.ymax { ctx.ymax = p.y }
        if p.y < ctx.ymin { ctx.ymin = p.y }
    }

    dx:f32 = kAlpha * (ctx.xmax - ctx.xmin)
    dy:f32 = kAlpha * (ctx.ymax - ctx.ymin)

    head :PointE = PointE_Init(linalg.point{ ctx.xmin - dx, ctx.ymin - dy }, max(u32))//!not use id
    tail :PointE = PointE_Init(linalg.point{ ctx.xmax + dx, ctx.ymin - dy }, max(u32))
    defer {
        delete(head.edges)
        delete(tail.edges)
    }

    slice.sort_by_cmp(ctx.pts[:], proc(a: ^PointE, b: ^PointE) -> slice.Ordering {
        if a.y < b.y { return .Less }
        if a.y == b.y { 
            if a.x < b.x { return .Less }
        }
        return .Greater
    })

    // ctx.pts[len(ctx.pts)-2] = head
    // ctx.pts[len(ctx.pts)-1] = tail

    non_zero_append(&ctx.maps, new_clone(Triangle{pts = [3]^PointE{ctx.pts[0], &head, &tail}}, context.temp_allocator))

    afHead : Node = Node_Init(ctx.maps[0].pts[1], ctx.maps[0])
    afMiddle : Node = Node_Init(ctx.maps[0].pts[0], ctx.maps[0])
    afTail : Node = Node_Init(ctx.maps[0].pts[2])

    ctx.front = AdvancingFront_Init(&afHead, &afTail)

    afHead.next = &afMiddle
    afMiddle.next = &afTail
    afMiddle.prev = &afHead
    afTail.prev = &afMiddle

    for i in 1..<len(ctx.pts) {
        node := AdvancingFront_LocateNode(&ctx.front, ctx.pts[i].x)
        if node == nil || node.point == nil || node.next == nil || node.next.point == nil {
            err = .nil_node
            return
        }

        non_zero_append(&ctx.maps, new_clone(Triangle{pts = [3]^PointE{ctx.pts[i], node.point, node.next.point}}, context.temp_allocator))
        tri := ctx.maps[len(ctx.maps) - 1]
        Triangle_MarkNeighbor(tri, node.triangle) or_return
        
        ctx.nodes[i-1] = Node_InitPts(ctx.pts[i])
        ctx.nodes[i-1].next = node.next
        ctx.nodes[i-1].prev = node
        node.next.prev = &ctx.nodes[i-1]
        node.next = &ctx.nodes[i-1]

        if Legalize(&ctx, tri) or_return {
        } else {
            MapTriangleToNodes(&ctx, tri) or_return
        }

        if ctx.pts[i].x <= node.point.x + math.epsilon(f32) {
            Fill(&ctx, node)
        }

        FillAdvancingFront(&ctx, &ctx.nodes[i-1])
        for e in ctx.pts[i].edges {
            EdgeEvent(&ctx, e, &ctx.nodes[i-1]) or_return
        }
    }

    
    tri := ctx.front.head.next.triangle
    p := ctx.front.head.next.point
    for tri != nil && !Triangle_GetConstrainedEdgeCW(tri, p) {
        tri = Triangle_NeighborCCW(tri, p)
    }

    if tri != nil {
        tris := mem.make_non_zeroed_dynamic_array([dynamic]^Triangle, context.temp_allocator)
        defer delete(tris)

        non_zero_append(&tris, tri)
        for len(tris) > 0 {
            tt := tris[len(tris) - 1]
            pop(&tris)
            
            if tt != nil && !tt.interior {
                tt.interior = true

                // Skip triangles that use super-triangle sentinels (head/tail have id = max(u32))
                if tt.pts[0].id != max(u32) && tt.pts[1].id != max(u32) && tt.pts[2].id != max(u32) {
                    non_zero_append(&ctx.indices, tt.pts[0].id)
                    non_zero_append(&ctx.indices, tt.pts[1].id)
                    non_zero_append(&ctx.indices, tt.pts[2].id)
                }

                for i in 0..<3 {
                    if !tt.constrainedEdge[i] {
                        non_zero_append(&tris, tt.neighbors[i])
                    }
                }
            }
        }
    }
    

    shrink(&ctx.indices)
    indices = ctx.indices[:]
    
    return
}

@(private = "file") Fill :: proc (ctx: ^TriangleCtx, node: ^Node) -> (err:Trianguate_Error = .None) {
    triangle := new_clone(Triangle{pts = [3]^PointE{node.prev.point, node.point, node.next.point}}, context.temp_allocator)

    non_zero_append(&ctx.maps, triangle)

    Triangle_MarkNeighbor(triangle, node.prev.triangle) or_return
    Triangle_MarkNeighbor(triangle, node.triangle) or_return
    

    node.prev.next = node.next
    node.next.prev = node.prev

    if Legalize(ctx, triangle) or_return {
    } else {
        MapTriangleToNodes(ctx, triangle) or_return
    }
    return
}

@(private = "file") FillAdvancingFront :: proc(ctx: ^TriangleCtx, node: ^Node) {
    node_ := node.next

    for (node_ != nil) && (node_.next != nil) {
        if LargeHole_DontFill(node_) do break
        Fill(ctx, node_)
        node_ = node_.next
    }

    node_ = node.prev;

    for (node_ != nil) && (node_.prev != nil) {
        if LargeHole_DontFill(node_) do break
        Fill(ctx, node_)
        node_ = node_.prev
    }

    if (node.next != nil) && (node.next.next != nil) {
        angle := BasinAngle(node)
        if angle < (3.0*math.PI/4.0) {
            FillBasin(ctx, node)
        }
    }
}

@(private = "file") BasinAngle :: proc "contextless" (node: ^Node) -> f32 {
    ax := node.point.x - node.next.next.point.x
    ay := node.point.y - node.next.next.point.y
    return math.atan2_f32(ay, ax)
}

@(private = "file") FillBasin :: proc (ctx: ^TriangleCtx, node: ^Node) {
    if Orient2d(node.point, node.next.point, node.next.next.point) == .CCW {
        ctx.basin.left_node = node.next.next
    } else {
        ctx.basin.left_node = node.next
    }

    ctx.basin.bottom_node = ctx.basin.left_node
    for ctx.basin.bottom_node.next != nil && 
        ctx.basin.bottom_node.point.y >= ctx.basin.bottom_node.next.point.y {
        ctx.basin.bottom_node = ctx.basin.bottom_node.next
    }
    if ctx.basin.bottom_node == ctx.basin.left_node {
        return
    }

    ctx.basin.right_node = ctx.basin.bottom_node
    for ctx.basin.right_node.next != nil && 
        ctx.basin.right_node.point.y < ctx.basin.right_node.next.point.y {
        ctx.basin.right_node = ctx.basin.right_node.next
    }
    if ctx.basin.right_node == ctx.basin.bottom_node {
        return
    }

    ctx.basin.width = ctx.basin.right_node.point.x - ctx.basin.left_node.point.x
    ctx.basin.left_highest = ctx.basin.left_node.point.y > ctx.basin.right_node.point.y

    FillBasinReq(ctx, ctx.basin.bottom_node)
}

@(private = "file") IsShallow :: proc "contextless" (ctx: ^TriangleCtx, node: ^Node) -> bool {
    height:f32

    if ctx.basin.left_highest {
        height = ctx.basin.left_node.point.y - node.point.y
    } else {
        height = ctx.basin.right_node.point.y - node.point.y
    }

    if ctx.basin.width > height {
        return true
    }
    return false
}

@(private = "file") FillBasinReq :: proc (ctx: ^TriangleCtx, node: ^Node) {
    node_ := node
    if IsShallow(ctx, node_) {
        return
    }

    Fill(ctx, node_)

    if node.prev == ctx.basin.left_node && node.next == ctx.basin.right_node {
        return
    } else if node.prev == ctx.basin.left_node {
        o := Orient2d(node.point, node.next.point, node.next.next.point)
        if o == .CW {
            return
        }
        node_ = node_.next
    } else if node_.next == ctx.basin.right_node {
        o := Orient2d(node_.point, node_.prev.point, node_.prev.prev.point)
        if o == .CCW {
            return
        }
        node_ = node_.prev
    } else {
        if node_.prev.point.y < node_.next.point.y {
            node_ = node_.prev
        } else {
            node_ = node_.next
        }
    }

    FillBasinReq(ctx, node_)
}

@(private = "file") LargeHole_DontFill :: proc "contextless" (node: ^Node) -> bool {
    nextNode := node.next
    prevNode := node.prev
    if !AngleExceeds90Degrees(node.point, nextNode.point, prevNode.point) {
        return false
    }
  
    if AngleIsNegative(node.point, nextNode.point, prevNode.point) {
        return true
    }
  
    next2Node := nextNode.next
    if next2Node != nil && !AngleExceedsPlus90DegreesOrIsNegative(node.point, next2Node.point, prevNode.point) {
        return false
    }
  
    prev2Node := prevNode.prev
    if prev2Node != nil && !AngleExceedsPlus90DegreesOrIsNegative(node.point, nextNode.point, prev2Node.point) {
        return false
    }
  
    return true
}
  
@(private = "file") AngleIsNegative :: proc "contextless" (origin, pa, pb: ^PointE) -> bool {
    angle := Angle(origin, pa, pb)
    return angle < 0
}
  
@(private = "file") AngleExceeds90Degrees :: proc "contextless" (origin, pa, pb: ^PointE) -> bool {
    angle := Angle(origin, pa, pb)
    return (angle > (math.PI/2.0)) || (angle < -(math.PI/2.0))
}
  
@(private = "file") AngleExceedsPlus90DegreesOrIsNegative :: proc "contextless" (origin, pa, pb: ^PointE) -> bool {
    angle := Angle(origin, pa, pb)
    return (angle > (math.PI/2.0)) || (angle < 0.0)
}
  
@(private = "file") Angle :: proc "contextless" (origin, pa, pb: ^PointE) -> f32 {
    px := origin.x
    py := origin.y
    ax := pa.x - px
    ay := pa.y - py
    bx := pb.x - px
    by := pb.y - py
    x := ax * by - ay * bx
    y := ax * bx + ay * by
    return math.atan2_f32(x, y)
}
  

@(private = "file") HoleAngle :: proc "contextless" (node: ^Node) -> f32 {
    ax := node.next.point.x - node.point.x
    ay := node.next.point.y - node.point.y
    bx := node.prev.point.x - node.point.x
    by := node.prev.point.y - node.point.y
    return math.atan2_f32(ax * by - ay * bx, ax * bx + ay * by)
}


TrianguatePolygons :: proc(poly:[]linalg.point,  nPoly:[]u32, allocator := context.allocator) -> (indices:[]u32, err:Trianguate_Error = .None) {
    indices_ := mem.make_non_zeroed_dynamic_array([dynamic]u32, context.temp_allocator)
    defer delete(indices_)

    idx :u32 = 0
    for n:u32 = 0;n < u32(len(nPoly));n += 1 {
        isHole := linalg.GetPolygonOrientation( poly[idx:idx+nPoly[n]]) == .Clockwise

        if !isHole {
            holes := mem.make_non_zeroed_dynamic_array([dynamic][]linalg.point, context.temp_allocator)
            holeIndices := mem.make_non_zeroed_dynamic_array([dynamic]u32, context.temp_allocator)
            defer delete(holes)
            defer delete(holeIndices)

            idx2 :u32 = 0
            for n2:u32 = 0;n2 < u32(len(nPoly));n2 += 1 {
                if n != n2 {
                    isHole = linalg.GetPolygonOrientation( poly[idx2:idx2+nPoly[n2]]) == .Clockwise
                    if isHole {
                        if linalg.PointInPolygon(poly[idx2], poly[idx:idx+nPoly[n]]) {
                            non_zero_append(&holes, poly[idx2:idx2+nPoly[n2]])
                            non_zero_append(&holeIndices, idx2)  
                        }
                    }
                }
                idx2 += nPoly[n2]
            }

            if len(holes) == 0 {
                indicesT := TrianguateSinglePolygon(poly[idx:idx+nPoly[n]], {idx},nil, context.temp_allocator) or_return
                defer delete(indicesT, context.temp_allocator)

                non_zero_append(&indices_, ..indicesT)
            } else {
                baseIdx := mem.make_non_zeroed_slice([]u32, len(holeIndices) + 1, context.temp_allocator)
                defer delete(baseIdx, context.temp_allocator)

                baseIdx[0] = idx
                intrinsics.mem_copy_non_overlapping(&baseIdx[1], &holeIndices[0], len(holeIndices) * size_of(u32))

                indicesT := TrianguateSinglePolygon(poly[idx:idx+nPoly[n]], baseIdx,holes[:], context.temp_allocator) or_return
                defer delete(indicesT, context.temp_allocator)

                non_zero_append(&indices_, ..indicesT)
            }
        }

        idx += nPoly[n]
    }

    indices = mem.make_non_zeroed_aligned_slice([]u32, len(indices_), 64, allocator)
    intrinsics.mem_copy_non_overlapping(raw_data(indices), raw_data(indices_), len(indices_) * size_of(u32))
	return
}
