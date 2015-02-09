// Copyright (c) 2015, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

#include <xs1.h>
#include <platform.h>
#include "ethernet.h"
#include "mii.h"
#include "print.h"
#include "debug_print.h"
#include "syscall.h"

#include "ports.h"

port p_ctrl = on tile[0]: XS1_PORT_1C;
#include "control.xc"

#include "helpers.xc"

#if ETHERNET_SUPPORT_HP_QUEUES

void test_rx(client ethernet_cfg_if cfg,
             streaming chanend c_rx_hp,
             client control_if ctrl)
{
  ethernet_macaddr_filter_t macaddr_filter;

  macaddr_filter.appdata = 0;
  for (int i = 0; i < 6; i++)
    macaddr_filter.addr[i] = i;
  cfg.add_macaddr_filter(0, 1, macaddr_filter);

  char seq_id = 0;
  int num_bytes = 0;
  int num_packets = 0;
  int done = 0;
  while (!done) {
    ethernet_packet_info_t packet_info;

    #pragma ordered
    select {
    case sin_char_array(c_rx_hp, (char *)&packet_info, sizeof(packet_info)):
      unsigned char rxbuf[ETHERNET_MAX_PACKET_SIZE];
      mii_receive_hp_packet(c_rx_hp, rxbuf, packet_info);
      num_bytes += packet_info.len;
      num_packets += 1;
      if (rxbuf[18] != seq_id) {
        debug_printf("Packet %d instead of %d\n", rxbuf[18], seq_id);
        _exit(1);
      }

      seq_id += 1;
      break;

    case ctrl.status_changed():
      status_t status;
      ctrl.get_status(status);
      if (status == STATUS_DONE)
        done = 1;
      break;
    }
  }
  debug_printf("Received %d packets, %d bytes\n", num_packets, num_bytes);
  ctrl.set_done();
}

#else // !ETHERNET_SUPPORT_HP_QUEUES

void test_rx(client ethernet_cfg_if cfg,
             client ethernet_rx_if rx,
             client control_if ctrl)
{
  ethernet_macaddr_filter_t macaddr_filter;

  macaddr_filter.appdata = 0;
  for (int i = 0; i < 6; i++)
    macaddr_filter.addr[i] = i;

  size_t index = rx.get_index();
  cfg.add_macaddr_filter(index, 0, macaddr_filter);

  char seq_id = 0;
  int num_bytes = 0;
  int num_packets = 0;
  int done = 0;
  while (!done) {
    #pragma ordered
    select {
    case rx.packet_ready():
      unsigned char rxbuf[ETHERNET_MAX_PACKET_SIZE];
      ethernet_packet_info_t packet_info;
      rx.get_packet(packet_info, rxbuf, ETHERNET_MAX_PACKET_SIZE);
      num_bytes += packet_info.len;
      num_packets += 1;
      if (rxbuf[18] != seq_id) {
        debug_printf("Packet %d instead of %d\n", rxbuf[18], seq_id);
        _exit(1);
      }

      seq_id += 1;
      break;

    case ctrl.status_changed():
      status_t status;
      ctrl.get_status(status);
      if (status == STATUS_DONE)
        done = 1;
      break;
    }
  }
  debug_printf("Received %d packets, %d bytes\n", num_packets, num_bytes);
  ctrl.set_done();
}

#endif // ETHERNET_SUPPORT_HP_QUEUES

#define NUM_CFG_IF 1
#define NUM_RX_LP_IF 1
#define NUM_TX_LP_IF 1

int main()
{
  ethernet_cfg_if i_cfg[NUM_CFG_IF];
  ethernet_rx_if i_rx_lp[NUM_RX_LP_IF];
  ethernet_tx_if i_tx_lp[NUM_TX_LP_IF];
  streaming chan c_rx_hp;
  streaming chan c_tx_hp;
  control_if i_ctrl[NUM_CFG_IF];

  par {
    on tile[1]: rgmii_ethernet_mac(i_cfg, NUM_CFG_IF,
                                   i_rx_lp, NUM_RX_LP_IF,
                                   i_tx_lp, NUM_TX_LP_IF,
                                   c_rx_hp, c_tx_hp,
                                   p_eth_rxclk, p_eth_rxer, p_eth_rxd_1000, p_eth_rxd_10_100,
                                   p_eth_rxd_interframe, p_eth_rxdv, p_eth_rxdv_interframe,
                                   p_eth_txclk_in, p_eth_txclk_out, p_eth_txer, p_eth_txen,
                                   p_eth_txd, eth_rxclk, eth_rxclk_interframe, eth_txclk,
                                   eth_txclk_out, ETHERNET_DISABLE_SHAPER);

    #if ETHERNET_SUPPORT_HP_QUEUES
    on tile[0]: test_rx(i_cfg[0], c_rx_hp, i_ctrl[0]);
    #else
    on tile[0]: test_rx(i_cfg[0], i_rx_lp[0], i_ctrl[0]);
    #endif

    on tile[0]: control(p_ctrl, i_ctrl, NUM_CFG_IF, NUM_CFG_IF);
  }
  return 0;
}

