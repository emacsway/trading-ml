(** Re-export module for the OrderTicket aggregate's execution
    strategies. Per ADR 0006: the main module of a directory
    shares its name with the directory and acts as the explicit
    re-export surface. Outside callers reach the abstraction at
    [Execution_management.Order_ticket.Strategies.Strategy] etc. *)

module Input = Input
module Decision = Decision
module Strategy = Strategy
module Immediate = Immediate
module Twap = Twap
module Vwap = Vwap
module Pov = Pov
module Iceberg = Iceberg
module Implementation_shortfall = Implementation_shortfall
