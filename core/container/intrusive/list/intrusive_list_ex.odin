package container_intrusive_list

import "base:intrinsics"

insert_after :: proc "contextless" (list: ^List, current_node: ^Node, new_node: ^Node) {
    if new_node != nil && current_node != nil {
        new_node.prev = current_node
        if current_node.next != nil {
            new_node.next = current_node.next
        } else {
            new_node.next = nil
            list.tail = new_node
        }
        current_node.next = new_node
    }
}

insert_before :: proc "contextless" (list: ^List, current_node: ^Node, new_node: ^Node) {
    if new_node != nil && current_node != nil {
        new_node.next = current_node
        if current_node.prev != nil {
            new_node.prev = current_node.prev
        } else {
            new_node.prev = nil
            list.head = new_node
        }
        current_node.prev = new_node
    }
}