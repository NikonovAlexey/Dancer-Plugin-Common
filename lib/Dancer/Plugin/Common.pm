package Dancer::Plugin::Common;

use strict;
use warnings;

use Dancer ':syntax';

use Dancer::Engine;

use Dancer::Plugin;
use Dancer::Plugin::ImageWork;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::FlashNote;
use Dancer::Plugin::uRBAC;

use FAW::uRoles;
use Data::Dump qw(dump);
use FindBin qw($Bin);
use Try::Tiny;
use POSIX 'strftime';
use JSON;
use Encode;

our $VERSION = '0.9';

my $conf = plugin_setting;

=head1 Обработка шаблонов

Набор процедур, которые выполняют взаимодействие и обработку шаблонов с помощью 
TemplateToolkit2.

=cut

=head2 template_process 

Отрисовать в вывод шаблон Template Toolkit с параметрами, указанными на входе.

На входе обязательно указать:
- имя шаблона, который станем отрисовывать;
- набор дополнительных параметров шаблона;

На выходе получить (и встроить) результат отрисовки шаблона;

=cut

sub template_process {
    my $template    = shift;
    my $params      = shift || { params => "none" };
    my $engine      = engine 'Template';
    my ( $tmpl, $result );
    
    $params->{rights} = \&rights;
    $tmpl = $engine->view($template);
    if ( ! defined($tmpl) ) {
        warning " === can't process $template file: is absend";
        return "can't process $template file: is absend";
    };
    
    try {
        $result = $engine->render($tmpl, $params);
    } catch {
        $result = "can't process $template file: is broken";
        warning " === can't process $template file: is broken";
    };
    
    return $result;
}

=head2 message_process

Служит для отрисовки сообщения по шаблону.
На входе указать message_id и набор параметров. В числе прочих параметров можно
использовать флаг flash, тогда отрисованный шаблон будет автоматически добавлен
к всплывающим сообщениям; и флаг log - ссылка на шаблон будет добавлена в общий
лог.

=cut

sub message_process {
    my $message_id      = shift;
    my $message_params  = shift || { params => "none" };
    my $result      = "";
    my $place_path  = '/../views/messages/';
    my $encode      = config->{engines}->{template_toolkit}->{encoding}
                        || "utf8";
    my $createflag  = config->{plugins}->{FlashMessage}->{create_messages} || 0;
    
    if ( -f "${Bin}${place_path}${message_id}" ) {
        try {
            my $engine = Template->new({
                INCLUDE_PATH    => "${Bin}${place_path}",
                ENCODING        => $encode,
            });
            $engine->process($message_id, $message_params, \$result);
        } catch {
            $result = "Message file $message_id is wrong.";
        };
    } else {
        $result = "Message file $message_id is absend."; 
        if ( $createflag == 1 ) {
            open(MESSAGEFILE, ">${Bin}${place_path}${message_id}");
            binmode MESSAGEFILE, ':utf8';
            say MESSAGEFILE $result;
            close(MESSAGEFILE);
        }
    }
    
    if ( $message_params->{flash} ) { flash $result;  }
    if ( $message_params->{log} ) { warning " === message $message_id"; }
    
    return $result;
}

=head2 asset

Разворачивает имя в полный путь в папке assets/project. Вторым аргументом можно указать тип.

=cut

sub assets {
    return template_process("blocks/assets.tt", { list => \@_ });
}


=head2 transliterate

Транслитерация русской строки в английскую раскладку согласно ГОСТ.

=cut

sub transliterate {
    my $str = shift || "";
    my %hs  = (
        'аА'=>'a',  'бБ'=>'b',  'вВ'=>'v',  'гГ'=>'g',  'дД'=>'d',
        'еЕ'=>'e',  'ёЁ'=>'jo', 'жЖ'=>'zh', 'зЗ'=>'z',  'иИ'=>'i',
        'йЙ'=>'j',  'кК'=>'k',  'лЛ'=>'l',  'мМ'=>'m',  'нН'=>'n',
        'оО'=>'o',  'пП'=>'p',  'рР'=>'r',  'сС'=>'s',  'тТ'=>'t',
        'уУ'=>'u',  'фФ'=>'f',  'хХ'=>'kh', 'цЦ'=>'c',  'чЧ'=>'ch',
        'шШ'=>'sh', 'щЩ'=>'shh','ъЪ'=>'',   'ыЫ'=>'y',  'ьЬ'=>'',
        'эЭ'=>'eh', 'юЮ'=>'ju', 'яЯ'=>'ja', ' '=>'_',
    );
    pop @{([ \map do{$str =~ s|[$_]|$hs{$_}|gi; }, keys %hs ])}, $str;
    
    return $str;
}

=head2 filtrate

Фильтрует ненужные спецсимволы в именах. Дополняет процедуру transliterate для
автоматического преобразования имени статьи.

=cut

sub filtrate {
    my $str = shift;
    
    $str =~ s/  / /g;
    $str =~ s/^ *//;
    $str =~ s/ *$//;
     
    $str =~ s/\W+/_/g;
    $str =~ s/__/_/g;
    $str =~ s/^_*//;
    $str =~ s/_*$//;
    
    return $str;
}

=head2 json_decode

Преобразовать строку на входе в perl-структуру (хэш). Считать, что строка передаётся в 
JSON-формате.

=cut

sub json_decode {
    my $json = shift || "";
    
    return JSON->new->utf8(0)->decode($json);
}

=head2 json_encode 

=cut

sub json_encode {
    my $json = shift || "";

    return JSON->new->utf8->encode($json);
}


=head1 Parsing pages

Набор процедур парсинга страничек

=cut

sub img_by_num {
    my ( $src, $id ) = @_;
    my ( $image, $suff );
    my $file = "";
    
    try {
        $image = schema->resultset('Image')->find({ id => $id }) || 0;
        $file  = $image->filename || "";
    } catch {
        return "$src$id";
    };
    
    return "$src$id" if $file eq "";
    return "<img internalid='$id' src='" . img_convert_name($file, "small") . "'>";
}

sub img_by_num_lb {
    my ( $src, $id ) = @_;
    my ( $image, $suff );
    my $file = "";
    my ( $name, $ext );

    try {
        $image = schema->resultset('Image')->find({ id => $id }) || 0;
        $file  = $image->filename || "";
        $suff  = $image->alias;
    } catch {
        return "$src$id";
    };
    
    return "$src$id" if $file eq "";
    return "<a href='" . img_convert_name($file, $suff) . "' rel='lightbox'><img internalid='$id' src='" . img_convert_name($file, "small") . "'></a>";
}

sub link_to_text {
    my ( $src, $link ) = @_;
    return "<a href='/page/$link'>$link</a>";
}

sub doc_by_num {
    my ( $src, $id ) = @_;
    my $doc;
    my $file = "";
    my $docname = "";
    
    if ( ! defined($id) ) { return "$src$id" };
    try {
        $doc    = schema->resultset('Document')->find({ id => $id }) || 0;
        $file   = $doc->filename || "";
        $docname= $doc->remark || "";
    } catch {
        return "$src$id";
    };

    $docname ||= $file;
    
    return "$src$id" if $file eq "";
    return "<a href='$file' target='_blank'>$docname</a>";
}

sub parsepage {
    my $text = $_[0];
    
    $text =~ s/(img\s*=\s*)(\d*)/&img_by_num($1,$2)/egm;
    $text =~ s/(imglb\s*=\s*)(\w*)/&img_by_num_lb($1,$2)/egm;
    $text =~ s/(link\s*=\s*)(\w*)/&link_to_text($1,$2)/egm;
    $text =~ s/(doc\s*=\s*)(\d*)/&doc_by_num($1,$2)/egm;
    return $text;
}

sub parseform {
    my $params = shift || "form: empty";
    my ( $tmpl, $result ) = ( "", "" );
    my ( $field, $type );
    
    warning " ====================== parsing ... ";
    $params = encode('UTF-8', $params);
    $params = JSON->new->utf8->decode($params) || { form => "empty" };
    
    my $form = $params->{name} || "form";
    
    foreach(@{$params->{items}}) {
        ( $field, $type ) = ( $_->{field}, $_->{type} );
        $tmpl .= template_process("components/form/$type", {
            name => $form .'-'. $field,
            id => $field,
            ext => $_,
        }) || "";
    };

    $result = template_process("components/form/_html", {
        formid => $params->{formid},
        formtitle => $params->{formtitle},
        action_jump => $params->{action},
        content => $tmpl,
        buttons => $params->{buttons},
    });
    
    return $result;
}

sub parsetest {
    return " some test string ";
}

sub now { 
    my $seconds_offset = shift || 0;
    return strftime "%Y-%m-%d %H:%M:%S", localtime(time + $seconds_offset);
}

sub convert_time {
    my $nixtime = shift || localtime(time);
    my $format  = shift || "%Y-%m-%d %H:%M:%S"; 
    
    return strftime( $format, $nixtime );
}


=head2 init_value 

Мы можем определять переменные в определённой секции сессии и считывать их при необходимости.

Формат вызова: (секция, переменная, значение по умолчанию).

Переменная задаётся либо в параметре на входе (через get-запрос после символа ?) либо в виде 
ранее сохранённого значения, либо в виде default-значения.

Мы можем не указывать значение по умолчанию. Тогда по умолчанию будет подставлена пуста строка "".

=cut

sub init_value {
    my ( $valuesection, $valuename, $default ) = @_;
    my $section;
    
    if ( ! defined($default) ) { $default = ""; }
    
    my $value = params->{$valuename} || session->{$valuesection}->{$valuename} || $default;
    $section = session->{$valuesection};
    $section->{$valuename} = $value; 
    session $valuesection => $section;
    
    return $value;
}

=head2 set_value

Принудительная установка значения.

=cut

sub set_value {
    my ( $valuesection, $valuename, $default ) = @_;
    my $section;
    
    if ( ! defined($default) ) { $default = ""; }
    
    $section = session->{$valuesection};
    $section->{$valuename} = $default; 
    session $valuesection => $section;
    
    return $default;

}

=head2 init_pager

Типичный пейджер содержит два значения: текущая страница и элементов на странице.

Поэтому его можно инициализировать простой процедурой. Только не следует
забывать указывать на входе, к какому разделу относится этот пейджер.

=cut

sub init_pager {
    my ( $section, $params ) = @_;
    my $defpage = ( $params->{page} ) ? $params->{page} : 1;
    my $defrows = ( $params->{itemperpage} ) ? $params->{itemperpage} : 25;
    my $page = init_value($section, "page", $defpage);
    my $rows = init_value($section, "itemperpage", $defrows);
    
    return ($page, $rows);
}


hook before_template_render => sub {
    my ($values) = @_;
    $values->{common} = config->{plugins}->{Common} || "";
    $values->{assets} = \&assets;
    $values->{parseform} = \&parseform;
};

register template_process   => \&template_process;
register message_process    => \&message_process;

register transliterate      => \&transliterate;
register filtrate           => \&filtrate;

register parsepage          => \&parsepage;
register parseform          => \&parseform;
register parsetest          => \&parsetest;

register now                => \&now;
register convert_time       => \&convert_time;

register json_decode        => \&json_decode;
register json_encode        => \&json_encode;

register init_value         => \&init_value;
register set_value          => \&set_value;
register init_pager         => \&init_pager;

register_plugin;

true;
