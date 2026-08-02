part of '../admin_dashboard_screen.dart';

extension on _AdminDashboardScreenState {
  // ==========================================================================
  // Destek talepleri + detay dialog
  // ==========================================================================

  // --- _buildSupportTicketsContent ---
  Widget _buildSupportTicketsContent() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadSupportTickets(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Hata: ${snapshot.error}'));
        }

        final tickets = snapshot.data ?? [];
        final openTickets = tickets.where((t) => t['status'] == 'open').length;
        final inProgressTickets = tickets
            .where((t) => t['status'] == 'in_progress')
            .length;
        final resolvedTickets = tickets
            .where((t) => t['status'] == 'resolved')
            .length;

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Destek Talepleri Yönetimi',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // İstatistik Kartları
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.pending_actions,
                        title: 'Bekleyen',
                        value: '$openTickets',
                        color: Colors.orange,
                        gradient: [
                          Colors.orange.shade400,
                          Colors.orange.shade600,
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.hourglass_bottom,
                        title: 'İşlemi Devam',
                        value: '$inProgressTickets',
                        color: Colors.blue,
                        gradient: [Colors.blue.shade400, Colors.blue.shade600],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.done_all,
                        title: 'Çözüldü',
                        value: '$resolvedTickets',
                        color: Colors.green,
                        gradient: [
                          Colors.green.shade400,
                          Colors.green.shade600,
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Talepler Listesi
                if (tickets.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.support_agent_outlined,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Destek talebi yok',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: tickets.length,
                    itemBuilder: (context, index) {
                      final ticket = tickets[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(12),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _getSupportTicketStatusColor(
                                ticket['status'],
                              ).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.support_agent,
                              color: _getSupportTicketStatusColor(
                                ticket['status'],
                              ),
                              size: 20,
                            ),
                          ),
                          title: Text(
                            ticket['subject'] ?? 'Başlıksız',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                ticket['message'] ?? '-',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(
                                    Icons.email,
                                    size: 12,
                                    color: Colors.grey.shade500,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      ticket['user_email'] ?? '-',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.access_time,
                                    size: 12,
                                    color: Colors.grey.shade500,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _formatDate(ticket['created_at']),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          trailing: Chip(
                            label: Text(
                              _getSupportTicketStatusText(ticket['status']),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            backgroundColor: _getSupportTicketStatusColor(
                              ticket['status'],
                            ).withOpacity(0.2),
                            labelStyle: TextStyle(
                              color: _getSupportTicketStatusColor(
                                ticket['status'],
                              ),
                            ),
                          ),
                          onTap: () => _showSupportTicketDetailDialog(ticket),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- _showSupportTicketDetailDialog ---
  void _showSupportTicketDetailDialog(Map<String, dynamic> ticket) {
    showDialog(
      context: context,
      builder: (context) => AdminTicketDetailDialog(
        ticket: ticket,
        onUpdate: () {
          _loadSupportTickets();
          setState(() {});
        },
      ),
    );
  }

  // --- _getSupportTicketStatusText ---
  String _getSupportTicketStatusText(String? status) {
    switch (status) {
      case 'open':
        return 'Açık';
      case 'in_progress':
        return 'İşlemi Devam';
      case 'resolved':
        return 'Çözüldü';
      case 'closed':
        return 'Kapalı';
      default:
        return 'Bilinmeyen';
    }
  }
}
