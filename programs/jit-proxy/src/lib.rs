use anchor_lang::prelude::*;

pub mod error;
pub mod instructions;
pub mod state;

use instructions::*;

declare_id!("Fzme515VV3TJhTyLaPqZ66n9B7PjG4P5ate7tDUeK81E");

#[program]
pub mod jit_proxy {
    use super::*;

    pub fn jit<'info>(ctx: Context<'info, Jit<'info>>, params: JitParams) -> Result<()> {
        instructions::jit(ctx, params)
    }

    pub fn jit_signed_msg<'info>(
        ctx: Context<'info, JitSignedMsg<'info>>,
        params: JitSignedMsgParams,
    ) -> Result<()> {
        instructions::jit_signed_msg(ctx, params)
    }

    pub fn check_order_constraints<'info>(
        ctx: Context<'info, CheckOrderConstraints<'info>>,
        constraints: Vec<OrderConstraint>,
    ) -> Result<()> {
        instructions::check_order_constraints(ctx, constraints)
    }

    pub fn arb_perp<'info>(ctx: Context<'info, ArbPerp<'info>>, market_index: u16) -> Result<()> {
        instructions::arb_perp(ctx, market_index)
    }
}
